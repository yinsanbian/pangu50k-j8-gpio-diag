`timescale 1ns/1ps
`default_nettype none
// LATENCY: testbench; full unmodified production timing and UART baud divisor.
module tb_gpio_production;
    localparam integer DIV = 434;
    localparam integer BIT_NS = DIV * 20;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, host_tx = 1;
    wire uart_tx;
    tri [33:0] j8_gpio;
    // No parameter overrides: 50MHz / 115200 baud / 1ms symbols /
    // 100us settle / 100us high-Z gap / 100 samples each direction.
    gpio_diag_top dut(.clk_50m(clk),.rst_n(rst_n),.uart_rx(host_tx),
        .uart_tx(uart_tx),.j8_gpio(j8_gpio));
    genvar g;
    generate for(g=0;g<34;g=g+1) begin: harness
        pulldown(j8_gpio[g]);
        assign #2 j8_gpio[g] = (g == 1 && dut.drive_en[0]) ? j8_gpio[0] :
            (g == 0 && dut.drive_en[1]) ? j8_gpio[1] : 1'bz;
    end endgenerate
    integer checks=0, observed_ab=0, observed_ba=0;
    integer bytes_received=0, bit_number;
    string received="";
    reg [7:0] decoded;
    reg [33:0] prior_driver=0, last_driver=0;
    reg prior_source=0;
    time stable_at=0, gap_at=0, shortest_settle=64'hffffffffffffffff;
    time observed_gap=0;
    integer serial_log;
    initial begin
        // fpga_msim_sim's automatic VCD dumps the full design. Select only
        // event-changing wires here so 12.4M clock cycles stay a small trace.
        $dumpfile("../reports/gpio_production.vcd");
        $dumpvars(0,dut.drive_en,dut.direction,dut.tx_gpio,dut.core_busy,dut.core_done,
            dut.u_ctrl.sample_strobe,dut.samples_ab,dut.samples_ba,
            dut.errors_ab,dut.errors_ba,host_tx,uart_tx);
    end

    task automatic verify(input bit condition,input string message);
        begin
            checks=checks+1;
            if(!condition) begin
                $display("TB_FAIL production time=%0t %s",$time,message);
                $fatal(1,"Production self-check failed");
            end
        end
    endtask
    always @(dut.drive_en or j8_gpio) begin
        if(rst_n && dut.drive_en != 0) begin
            if(prior_driver != dut.drive_en ||
                prior_source != j8_gpio[dut.drive_en[0] ? 0 : 1]) stable_at=$time;
            prior_source=j8_gpio[dut.drive_en[0] ? 0 : 1];
        end
        if(prior_driver != 0 && dut.drive_en == 0) gap_at=$time;
        if(prior_driver == 0 && dut.drive_en != 0 && last_driver != 0 &&
            last_driver != dut.drive_en) begin
            observed_gap=$time-gap_at;
            verify(observed_gap >= 5000*20,"real high-Z turnaround is at least 100us");
        end
        if(dut.drive_en != 0) last_driver=dut.drive_en;
        prior_driver=dut.drive_en;
    end
    always @(posedge clk) begin
        if(dut.internal_rst_n) begin
            verify((dut.drive_en & (dut.drive_en-34'd1)) == 0,"one GPIO output maximum");
            verify(dut.core_busy || dut.drive_en == 0,"idle and reporting are high-Z");
            if(dut.u_ctrl.sample_strobe) begin
                verify($time-stable_at >= 5000*20,"sampling waits at least 100us after physical output change");
                if($time-stable_at < shortest_settle) shortest_settle=$time-stable_at;
                verify(j8_gpio[dut.direction ? 0 : 1] === dut.tx_gpio,"external return reaches receiving pin");
                if(dut.direction) observed_ba=observed_ba+1;
                else observed_ab=observed_ab+1;
            end
        end
    end
    initial begin
        serial_log=$fopen("production_uart_observed.txt","w");
        forever begin
            @(negedge uart_tx);
            if(rst_n) begin
                #(BIT_NS/2); verify(uart_tx===0,"115200 UART start bit");
                for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
                    #BIT_NS; decoded[bit_number]=uart_tx;
                end
                #BIT_NS; verify(uart_tx===1,"115200 UART stop bit");
                received={received,decoded};
                bytes_received=bytes_received+1;
                $fwrite(serial_log,"%c",decoded);
                #(BIT_NS/2);
            end
        end
    end
    task automatic send_byte(input [7:0] data);
        integer b;
        begin
            @(negedge clk); host_tx=0;
            repeat(DIV) @(negedge clk);
            for(b=0;b<8;b=b+1) begin
                host_tx=data[b]; repeat(DIV) @(negedge clk);
            end
            host_tx=1; repeat(DIV+2) @(negedge clk);
        end
    endtask
    task automatic send_text(input string text);
        integer n;
        begin
            for(n=0;n<text.len();n=n+1) send_byte(text[n]);
        end
    endtask
    task automatic await_quiet;
        integer cycles,quiet;
        begin: waiting
            quiet=0;
            for(cycles=0;cycles<14000000;cycles=cycles+1) begin
                @(posedge clk); #1;
                if(!dut.command_busy && !dut.busy_pending && uart_tx) quiet=quiet+1;
                else quiet=0;
                if(quiet==20) disable waiting;
            end
            verify(0,"default-timing completion timeout");
        end
    endtask
    task automatic command(input string text,input string expected);
        begin
            received=""; send_text(text); await_quiet();
            if(received != expected) $display("EXPECTED=[%s] ACTUAL=[%s]",expected,received);
            verify(received==expected,"full 115200 baud ASCII response");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst_n=1;
        await_quiet();
        verify(received.len()==184,"production boot complete");
        verify(dut.drive_en==0 && !dut.core_busy,"KEY1 reset boot remains high-Z");
        verify(dut.u_tx.DIV==434 && dut.u_rx.DIV==434,"production divisor rounds to 434");
        command("PAIR 01\015\n","SELECT PAIR=01 J8=03/04 NEED_ARM\015\n");
        command("ARM\015\n","ARMED: harness and both input biases confirmed by operator.\015\n");
        command("RUN SMOKE\015\n",{
            "RUN MODE=SMOKE  J8=03/04\015\n",
            "PAIR=01 J8=03/04 MODE=SMOKE  ABORTED=0\015\n",
            "03->04: PASS         errors=0000000000/0000000100 MAX10K=0000000000\015\n",
            "04->03: PASS         errors=0000000000/0000000100 MAX10K=0000000000\015\n",
            "NOTE=PATH_ONLY; INVALID=NO_LOOPBACK_OR_STUCK/ABORT. RETEST_REQUIRED.\015\n"});
        verify(dut.samples_ab==100 && dut.samples_ba==100 && observed_ab==100 && observed_ba==100,
            "production samples exactly 100 in each direction");
        verify(dut.errors_ab==0 && dut.errors_ba==0 && dut.status_ab==0 && dut.status_ba==0,
            "production healthy loopback PASS with zero errors");
        verify(observed_gap==100000,"default high-Z gap exactly 5000 clocks");
        verify(shortest_settle==100000,"default sample wait exactly 5000 clocks");
        verify(dut.drive_en==0 && !dut.core_busy,"completed production run releases all GPIO");
        $fclose(serial_log);
        $display("TB_PASS gpio_production checks=%0d samples=%0d/%0d min_settle_ns=%0d gap_ns=%0d uart_div=%0d bytes=%0d",
            checks,observed_ab,observed_ba,shortest_settle,observed_gap,DIV,bytes_received);
        $finish;
    end
    initial begin
        #500000000;
        $fatal(1,"TB_FAIL gpio_production global timeout");
    end
endmodule
`default_nettype wire
