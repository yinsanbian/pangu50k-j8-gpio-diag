`timescale 1ns/1ps
`default_nettype none
// LATENCY: external harness 2 ns; independent UART decoder samples bit centers.
module tb_gpio_uart;
    localparam integer DIV = 16;
    localparam integer BIT_NS = DIV * 10;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, host_tx = 1;
    wire uart_tx;
    tri [33:0] j8_gpio;
    reg [5:0] harness_a = 0, harness_b = 1;
    reg loopback_open = 0;
    integer fault_kind = 0;
    wire invert_ab = fault_kind == 1 || (fault_kind == 2 && dut.samples_ab == 50);
    gpio_diag_top #(.CLK_HZ(1600000), .BAUD(100000),
        .SYMBOL_CYCLES(16), .SETTLE_CYCLES(8), .GAP_CYCLES(8),
        .SMOKE_SAMPLES(100), .NORMAL_SAMPLES(10000), .STRESS_SAMPLES(100000)) dut (
        .clk_50m(clk), .rst_n(rst_n), .uart_rx(host_tx),
        .uart_tx(uart_tx), .j8_gpio(j8_gpio));
    genvar g;
    generate for (g=0;g<34;g=g+1) begin: harness
        pulldown(j8_gpio[g]);
        assign #2 j8_gpio[g] = (!loopback_open && !dut.drive_en[g] &&
            g == harness_b && dut.drive_en[harness_a]) ?
                (invert_ab ? ~j8_gpio[harness_a] : j8_gpio[harness_a]) :
            (!loopback_open && !dut.drive_en[g] && g == harness_a &&
            dut.drive_en[harness_b]) ? j8_gpio[harness_b] : 1'bz;
    end endgenerate
    integer cases = 0, checks = 0, starts = 0, completions = 0, drive_cycles = 0;
    reg completed_during_ack = 0;
    string received = "";
    integer tx_byte_count = 0;
    reg [7:0] decoded;
    integer bit_number;
    integer serial_log;

    task automatic verify(input bit condition, input string message);
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("TB_FAIL uart case=%0d time=%0t %s", cases, $time, message);
                $fatal(1, "UART self-check failed");
            end
        end
    endtask

    // Decode the output pin directly. No use of RTL byte-handshake signals.
    initial begin
        serial_log = $fopen("uart_observed.txt", "w");
        forever begin
            @(negedge uart_tx);
            if (rst_n) begin
                #(BIT_NS/2);
                verify(uart_tx === 0, "UART start-bit center");
                for (bit_number=0;bit_number<8;bit_number=bit_number+1) begin
                    #BIT_NS;
                    decoded[bit_number] = uart_tx;
                end
                #BIT_NS;
                verify(uart_tx === 1, "UART stop-bit center");
                received = {received, decoded};
                tx_byte_count = tx_byte_count + 1;
                $fwrite(serial_log, "%c", decoded);
                #(BIT_NS/2);
            end
        end
    end

    always @(posedge clk) begin
        if (dut.internal_rst_n) begin
            if (dut.start) starts = starts + 1;
            if (dut.core_done) completions = completions + 1;
            if (dut.core_done && dut.report_busy) completed_during_ack = 1;
        end
    end
    always @(negedge clk) begin
        if (rst_n && dut.internal_rst_n) begin
            verify((^dut.drive_en) !== 1'bx, "known GPIO output enables");
            verify((dut.drive_en & (dut.drive_en - 34'd1)) == 0, "GPIO drivers one-hot or zero");
            verify(dut.core_busy || dut.drive_en == 0, "idle/report GPIO high-Z");
            if (dut.drive_en != 0) begin
                drive_cycles = drive_cycles + 1;
                verify(dut.drive_en[harness_a] || dut.drive_en[harness_b], "only harness endpoint is driven");
            end
        end
    end

    task automatic send_byte(input [7:0] data, input bit valid_stop);
        integer b;
        begin
            @(negedge clk); host_tx = 0;
            repeat(DIV) @(negedge clk);
            for(b=0;b<8;b=b+1) begin
                host_tx = data[b];
                repeat(DIV) @(negedge clk);
            end
            host_tx = valid_stop;
            repeat(DIV) @(negedge clk);
            host_tx = 1;
            repeat(2) @(negedge clk);
        end
    endtask
    task automatic send_text(input string text);
        integer n;
        begin
            for(n=0;n<text.len();n=n+1) send_byte(text[n],1);
        end
    endtask
    task automatic await_quiet;
        integer cycles, quiet;
        begin: waiting
            quiet = 0;
            for(cycles=0;cycles<4000000;cycles=cycles+1) begin
                @(posedge clk); #1;
                if (!dut.command_busy && !dut.busy_pending && uart_tx) quiet=quiet+1;
                else quiet=0;
                if(quiet==20) disable waiting;
            end
            verify(0,"serial/core completion timeout");
        end
    endtask
    task automatic compare_text(input string expected);
        begin
            if(received != expected) begin
                $display("EXPECTED bytes=%0d text=[%s]",expected.len(),expected);
                $display("ACTUAL bytes=%0d text=[%s]",received.len(),received);
            end
            verify(received == expected,"full UART ASCII response differs");
            verify(dut.drive_en == 0,"response completed with all GPIO high-Z");
            $display("CASE_PASS uart n=%0d bytes=%0d starts=%0d completions=%0d",cases,received.len(),starts,completions);
        end
    endtask
    task automatic command(input string text, input string expected);
        begin
            cases=cases+1; received="";
            send_text(text);
            await_quiet();
            compare_text(expected);
        end
    endtask

    function automatic string decimal_two(input integer number);
        decimal_two = {$sformatf("%0d",number/10),$sformatf("%0d",number%10)};
    endfunction
    function automatic string decimal_ten(input integer number);
        string padded;
        padded = {"0000000000",$sformatf("%0d",number)};
        decimal_ten = padded.substr(padded.len()-10,padded.len()-1);
    endfunction
    function automatic string result_text(input integer pair, input integer a, input integer b,
        input string mode_name, input bit interrupted,
        input string status0, input integer error0, input integer sample0, input integer block0,
        input string status1, input integer error1, input integer sample1, input integer block1);
        result_text = {$sformatf("PAIR=%s J8=%s/%s MODE=%s ABORTED=%0d\015\n",decimal_two(pair),decimal_two(a),decimal_two(b),mode_name,interrupted),
            $sformatf("%s->%s: %s errors=%s/%s MAX10K=%s\015\n",decimal_two(a),decimal_two(b),status0,decimal_ten(error0),decimal_ten(sample0),decimal_ten(block0)),
            $sformatf("%s->%s: %s errors=%s/%s MAX10K=%s\015\n",decimal_two(b),decimal_two(a),status1,decimal_ten(error1),decimal_ten(sample1),decimal_ten(block1)),
            "NOTE=PATH_ONLY; INVALID=NO_LOOPBACK_OR_STUCK/ABORT. RETEST_REQUIRED.\015\n"};
    endfunction

    string error_line = "ERR INVALID_COMMAND_OR_LINE (uppercase; max 31 characters)\015\n";
    string not_armed = "INVALID: NOT_ARMED_OR_REFERENCE_UNCONFIRMED. GPIO HIGH-Z.\015\n";
    string armed_line = "ARMED: harness and both input biases confirmed by operator.\015\n";
    string busy_line = "BUSY: command rejected. Wait for report, then resend.\015\n";
    string expected, retained, line;
    integer pair, before_starts, before_drive, stopped_samples_ab, stopped_samples_ba;
    initial begin
        repeat(5) @(negedge clk);
        rst_n=1;
        await_quiet();
        cases=cases+1;
        compare_text({"PANGU50K MES50HP J8 GPIO DIAGNOSTIC\015\n",
            "FPGA=PGL50H-6IFBG484 UART=115200 8N1\015\n",
            "INVALID: NOT_ARMED / NO_LOOPBACK. GPIO HIGH-Z.\015\n",
            "Send HELP. Fit 1k loopback and TWO 10k pulldowns, then ARM.\015\n"});
        command("REPORT\015\n","INVALID: NO_RESULT. GPIO HIGH-Z.\015\n");
        command("HELP\015\n",{"PAIR 01..17 | CROSS 03 09 | REF OK | ARM\015\n",
            "RUN SMOKE | RUN NORMAL | RUN STRESS | STOP | REPORT | HELP\015\n",
            "ARM confirms harness and BOTH pulldowns. RUN consumes ARM.\015\n",
            "CROSS requires a verified reference and REF OK.\015\n"});
        command("RUN SMOKE\015\n",not_armed);
        verify(starts==0 && drive_cycles==0,"unarmed startup never drove a pin");
        // Check every PAIR parser mapping and CR/LF once-only termination.
        for(pair=1;pair<=17;pair=pair+1) begin
            command($sformatf("PAIR %s\015\n",decimal_two(pair)),
                $sformatf("SELECT PAIR=%s J8=%s/%s NEED_ARM\015\n",decimal_two(pair),decimal_two(pair*2+1),decimal_two(pair*2+2)));
            verify(dut.selected_a == pair*2-2 && dut.selected_b == pair*2-1,
                "PAIR physical-to-index mapping");
        end
        command("PAIR 00\015",error_line);
        command("PAIR 18\n",error_line);
        command("PAIR A1\015\n",error_line);
        command("pair 01\015\n",error_line);
        command("CROSS 03 03\015\n",error_line);
        command("CROSS 02 36\015\n",error_line);
        command("CROSS 03 37\015\n",error_line);
        command("REF OK\015\n",error_line);
        command("PAIR 01 \015\n",error_line);
        // Overflow and a malformed UART frame invalidate their complete lines.
        before_starts=starts; before_drive=drive_cycles;
        command("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAARUN SMOKE\015\n",error_line);
        cases=cases+1; received="";
        send_text("AR"); send_byte("M",0); send_text("\015\n");
        await_quiet(); compare_text(error_line);
        verify(starts==before_starts && drive_cycles==before_drive,"malformed lines never initiate a test");
        command("PAIR 01\015\n","SELECT PAIR=01 J8=03/04 NEED_ARM\015\n");
        harness_a=0; harness_b=1;
        command("ARM\015\n",armed_line);
        retained=result_text(1,3,4,"SMOKE ",0,"PASS        ",0,100,0,"PASS        ",0,100,0);
        command("RUN SMOKE\015\n",{"RUN MODE=SMOKE  J8=03/04\015\n",retained});
        verify(completed_during_ack,"accelerated result completed during RUN acknowledgment");
        verify(starts==1 && completions==1,"CRLF started exactly one test");
        command("RUN SMOKE\015\n",not_armed);
        command("PAIR 17\015\n","SELECT PAIR=17 J8=35/36 NEED_ARM\015\n");
        command("REPORT\015\n",retained);
        verify(dut.last_pair==1 && dut.last_a==0 && dut.last_b==1,"REPORT retains original metadata after reselection");
        command("CROSS 03 36\015\n","SELECT PAIR=00 J8=03/36 NEED_ARM\015\n");
        harness_a=0; harness_b=33;
        command("ARM\015\n",armed_line);
        command("RUN SMOKE\015\n",not_armed);
        command("REF OK\015\n","REFERENCE_CONFIRMED: operator has verified the reference IO.\015\n");
        retained=result_text(0,3,36,"SMOKE ",0,"PASS        ",0,100,0,"PASS        ",0,100,0);
        command("RUN SMOKE\015\n",{"RUN MODE=SMOKE  J8=03/36\015\n",retained});
        command("CROSS 36 03\015\n","SELECT PAIR=00 J8=36/03 NEED_ARM\015\n");
        harness_a=33; harness_b=0;
        command("ARM\015\n",armed_line);
        command("RUN SMOKE\015\n",not_armed);
        command("REF OK\015\n","REFERENCE_CONFIRMED: operator has verified the reference IO.\015\n");
        retained=result_text(0,36,3,"NORMAL",0,"PASS        ",0,10000,0,"PASS        ",0,10000,0);
        command("RUN NORMAL\015\n",{"RUN MODE=NORMAL J8=36/03\015\n",retained});
        command("ARM\015\n",armed_line);
        retained=result_text(0,36,3,"STRESS",0,"PASS        ",0,100000,0,"PASS        ",0,100000,0);
        command("RUN STRESS\015\n",{"RUN MODE=STRESS J8=36/03\015\n",retained});
        // Genuine external open produces INVALID with correct per-direction totals.
        command("PAIR 01\015\n","SELECT PAIR=01 J8=03/04 NEED_ARM\015\n");
        harness_a=0; harness_b=1; loopback_open=1;
        command("ARM\015\n",armed_line);
        retained=result_text(1,3,4,"SMOKE ",0,"INVALID     ",50,100,50,"INVALID     ",50,100,50);
        command("RUN SMOKE\015\n",{"RUN MODE=SMOKE  J8=03/04\015\n",retained});
        loopback_open=0;
        fault_kind=1;
        command("ARM\015\n",armed_line);
        retained=result_text(1,3,4,"SMOKE ",0,"FAIL        ",100,100,100,"PASS        ",0,100,0);
        command("RUN SMOKE\015\n",{"RUN MODE=SMOKE  J8=03/04\015\n",retained});
        fault_kind=2;
        command("ARM\015\n",armed_line);
        retained=result_text(1,3,4,"SMOKE ",0,"INTERMITTENT",1,100,1,"PASS        ",0,100,0);
        command("RUN SMOKE\015\n",{"RUN MODE=SMOKE  J8=03/04\015\n",retained});
        fault_kind=0;
        // Active test: reject ordinary commands, coalesce BUSY, then STOP.
        command("ARM\015\n",armed_line);
        cases=cases+1; received="";
        send_text("RUN STRESS\015\n");
        repeat(1000) @(negedge clk);
        verify(dut.core_busy,"long run remains busy");
        send_text("PAIR 02\015\n");
        send_text("STOP\015\n");
        await_quiet();
        stopped_samples_ab=dut.last_samples_ab; stopped_samples_ba=dut.last_samples_ba;
        verify(stopped_samples_ab>0 && stopped_samples_ab<100000 && stopped_samples_ba==0,
            "STOP preserves AB partial count without beginning BA");
        retained=result_text(1,3,4,"STRESS",1,"INVALID     ",0,stopped_samples_ab,0,
            "INVALID     ",0,stopped_samples_ba,0);
        expected={"RUN MODE=STRESS J8=03/04\015\n",retained,busy_line};
        compare_text(expected);
        verify(dut.selected_pair==1,"busy PAIR command had no selection effect");
        command("REPORT\015\n",retained);
        command("RUN NORMAL\015\n",not_armed);
        command("STOP\015\n","STOP: outputs disabled; incomplete run is INVALID.\015\n");
        // Completion window regression: prepare a UART line normally, then
        // deliver its terminator at parser level in the single core_done cycle.
        // This stimulus checks command arbitration; GPIO still uses the harness.
        command("ARM\015\n",armed_line);
        cases=cases+1; received="";
        send_text("RUN NORMAL\015\n");
        while(dut.samples_ba<9800) @(negedge clk);
        send_text("PAIR 02");
        @(posedge dut.core_done);
        @(negedge clk);
        verify(!dut.core_busy && !dut.report_busy && dut.core_done,
            "isolated completed-core window before result report");
        verify(dut.command_busy,"core_done closes command acceptance window");
        force dut.rx_data=8'h0d;
        force dut.rx_valid=1'b1;
        @(posedge clk); #1;
        release dut.rx_data;
        release dut.rx_valid;
        await_quiet();
        retained=result_text(1,3,4,"NORMAL",0,"PASS        ",0,10000,0,"PASS        ",0,10000,0);
        compare_text({"RUN MODE=NORMAL J8=03/04\015\n",retained,busy_line});
        verify(dut.selected_pair==1,"PAIR is rejected at the completed-core window");
        $fclose(serial_log);
        $display("TB_PASS gpio_uart cases=%0d checks=%0d tx_bytes=%0d starts=%0d completions=%0d",
            cases,checks,tx_byte_count,starts,completions);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"TB_FAIL gpio_uart global timeout");
    end
endmodule
`default_nettype wire
