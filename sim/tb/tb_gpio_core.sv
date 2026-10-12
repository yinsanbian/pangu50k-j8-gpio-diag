`timescale 1ns/1ps
`default_nettype none
// LATENCY: testbench; each external harness transfer has 2 ns delay.
// This models connector-side return wiring, not an internal TX/RX shortcut.
module tb_gpio_core;
    localparam integer SYMBOL = 16;
    localparam integer SETTLE = 8;
    localparam integer GAP = 8;
    localparam [1:0] PASS = 0, INTERMITTENT = 1, FAIL = 2, INVALID = 3;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, start = 0, abort = 0, qualified = 1;
    reg [5:0] pin_a = 0, pin_b = 1;
    reg [1:0] mode = 0;
    wire [33:0] drive_en, rx_raw;
    wire tx_data, busy, done, aborted, direction;
    wire [1:0] status_ab, status_ba;
    wire [31:0] errors_ab, errors_ba, samples_ab, samples_ba;
    wire [31:0] block_errors_ab, block_errors_ba;
    tri [33:0] j8_gpio;
    reg [5:0] harness_a = 0, harness_b = 1;
    integer fault = 0;
    // 0 healthy, 1 open, 2 stuck high, 3 AB inversion, 4 one AB error,
    // 5 BA inversion, 6 stress AB errors across several 10k time blocks,
    // 7/8 exactly 10/11 AB errors for the classification threshold boundary.
    wire intermittent_ab = (fault == 4 && samples_ab == 50);
    wire stress_ab = (fault == 6 &&
        (samples_ab == 50 || samples_ab == 5000 || samples_ab == 10050 ||
         samples_ab == 50050 || samples_ab == 90050));
    wire corrupt_ab = (fault == 3) || intermittent_ab || stress_ab ||
        (fault == 7 && samples_ab < 10) || (fault == 8 && samples_ab < 11);
    wire corrupt_ba = (fault == 5);
    genvar g;
    generate for (g = 0; g < 34; g = g + 1) begin: harness
        // The real hardware requires a verified external weak bias on BOTH
        // loopback endpoints, because the input endpoint changes direction.
        pulldown (j8_gpio[g]);
        assign #2 j8_gpio[g] =
            (fault == 2 && !drive_en[g] &&
                ((g == harness_a) || (g == harness_b))) ? 1'b1 :
            (fault != 1 && !drive_en[g] && g == harness_b &&
                drive_en[harness_a]) ?
                (corrupt_ab ? ~j8_gpio[harness_a] : j8_gpio[harness_a]) :
            (fault != 1 && !drive_en[g] && g == harness_a &&
                drive_en[harness_b]) ?
                (corrupt_ba ? ~j8_gpio[harness_b] : j8_gpio[harness_b]) : 1'bz;
    end endgenerate

    gpio_pair_mux io(.drive_en(drive_en), .tx_data(tx_data),
        .j8_gpio(j8_gpio), .rx_raw(rx_raw));
    gpio_test_ctrl #(.CLK_HZ(50000000), .SYMBOL_CYCLES(SYMBOL),
        .SETTLE_CYCLES(SETTLE), .GAP_CYCLES(GAP),
        .SMOKE_SAMPLES(100), .NORMAL_SAMPLES(10000),
        .STRESS_SAMPLES(100000)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .abort(abort),
        .pin_a(pin_a), .pin_b(pin_b), .mode(mode), .qualified(qualified),
        .rx_raw(rx_raw), .drive_en(drive_en), .tx_data(tx_data),
        .busy(busy), .done(done), .status_ab(status_ab), .status_ba(status_ba),
        .errors_ab(errors_ab), .errors_ba(errors_ba),
        .samples_ab(samples_ab), .samples_ba(samples_ba), .aborted(aborted),
        .block_errors_ab(block_errors_ab), .block_errors_ba(block_errors_ba),
        .direction(direction));

    integer cases = 0, checks = 0, drive_cycles = 0;
    integer gold_samples[0:1], gold_errors[0:1], gold_zeros[0:1], gold_ones[0:1];
    integer gold_block[0:1], gold_max_block[0:1];
    integer gold_goal = 100;
    reg [1:0] gold_mode = 0;
    reg [15:0] gold_lfsr[0:1];
    integer zero_cycles = 0;
    reg [33:0] last_driver = 0;
    reg monitor_run = 0, monitor_drive_allowed = 1;
    integer s, d, idx;
    reg expected_bit, returned_bit, expected_corrupt;
    task automatic verify(input bit condition, input string message);
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("TB_FAIL core case=%0d time=%0t %s", cases, $time, message);
                $fatal(1, "Core self-check failed");
            end
        end
    endtask

    // Safety is checked independently of the RTL state encoding.
    always @(negedge clk) begin
        if (rst_n) begin
            verify((^drive_en) !== 1'bx, "unknown output enable");
            verify((drive_en & (drive_en - 34'd1)) == 0, "multiple GPIO output drivers");
            verify(busy || drive_en == 0, "GPIO drives outside active test");
            if (!monitor_drive_allowed)
                verify(drive_en == 0, "unqualified/illegal request enables GPIO");
            if (drive_en == 0) zero_cycles = zero_cycles + 1;
            else begin
                drive_cycles = drive_cycles + 1;
                verify(drive_en[harness_a] || drive_en[harness_b], "nonselected GPIO driven");
                if (last_driver != 0 && drive_en != last_driver)
                    verify(zero_cycles >= GAP, "direction changed without full high-Z gap");
                last_driver = drive_en;
                zero_cycles = 0;
            end
        end else begin
            verify(drive_en === 34'd0, "reset must immediately release all IO");
            last_driver = 0;
            zero_cycles = 0;
        end
    end

    // Independent golden pattern and counters. Internal strobe/index are
    // observation points only; all received values come through external nets.
    always @(posedge clk) begin
        if (rst_n && monitor_run && dut.sample_strobe) begin
            d = direction ? 1 : 0;
            idx = gold_samples[d];
            verify(dut.symbol_index == idx, "sample index skips or duplicates a symbol");
            if (gold_mode == 0) expected_bit = idx[0];
            else if (idx < (gold_goal >> 2)) expected_bit = 0;
            else if (idx < (gold_goal >> 1)) expected_bit = 1;
            else if (idx < gold_goal - (gold_goal >> 2)) expected_bit = idx[0];
            else begin
                expected_bit = gold_lfsr[d][15];
                gold_lfsr[d] = {gold_lfsr[d][14:0], gold_lfsr[d][15] ^
                    gold_lfsr[d][13] ^ gold_lfsr[d][12] ^ gold_lfsr[d][10]};
            end
            verify(tx_data === expected_bit, "pattern differs from independent reference");
            expected_corrupt = d == 0 ?
                ((fault == 3) || (fault == 4 && idx == 50) ||
                (fault == 7 && idx < 10) || (fault == 8 && idx < 11) ||
                (fault == 6 && (idx == 50 || idx == 5000 || idx == 10050 ||
                               idx == 50050 || idx == 90050))) : fault == 5;
            returned_bit = fault == 1 ? 1'b0 : fault == 2 ? 1'b1 :
                (expected_corrupt ? ~expected_bit : expected_bit);
            verify(j8_gpio[d == 0 ? harness_b : harness_a] === returned_bit,
                "external return net differs from configured harness model");
            if (returned_bit) gold_ones[d] = gold_ones[d] + 1;
            else gold_zeros[d] = gold_zeros[d] + 1;
            if ((idx % 10000) == 0) gold_block[d] = 0;
            if (returned_bit != expected_bit) begin
                gold_errors[d] = gold_errors[d] + 1;
                gold_block[d] = gold_block[d] + 1;
                if (gold_block[d] > gold_max_block[d]) gold_max_block[d] = gold_block[d];
            end
            gold_samples[d] = gold_samples[d] + 1;
        end
    end

    function automatic [1:0] reference_status(input integer dir);
        if (gold_ones[dir] == 0 || gold_zeros[dir] == 0) reference_status = INVALID;
        else if (gold_errors[dir] == 0) reference_status = PASS;
        else if (gold_errors[dir] * 10 <= gold_samples[dir]) reference_status = INTERMITTENT;
        else reference_status = FAIL;
    endfunction

    task automatic prepare(input integer a, input integer b, input integer m,
        input integer f, input bit q);
        begin
            @(negedge clk);
            cases = cases + 1;
            monitor_run = 0;
            last_driver = 0; zero_cycles = 0;
            pin_a = a[5:0]; pin_b = b[5:0]; mode = m[1:0]; qualified = q;
            harness_a = a < 34 ? a[5:0] : 0;
            harness_b = b < 34 ? b[5:0] : 1;
            fault = f; abort = 0; start = 0;
            gold_mode = m[1:0];
            gold_goal = m == 0 ? 100 : m == 1 ? 10000 : 100000;
            for (s = 0; s < 2; s = s + 1) begin
                gold_samples[s] = 0; gold_errors[s] = 0;
                gold_zeros[s] = 0; gold_ones[s] = 0;
                gold_block[s] = 0; gold_max_block[s] = 0;
                gold_lfsr[s] = 16'h1ace;
            end
            monitor_drive_allowed = q && a < 34 && b < 34 && a != b && m < 3;
            monitor_run = monitor_drive_allowed;
            start = 1;
            @(negedge clk); start = 0;
        end
    endtask

    task automatic await_done(input integer max_cycles);
        integer cycle;
        begin: waiting
            for (cycle = 0; cycle < max_cycles; cycle = cycle + 1) begin
                @(posedge clk); #1;
                if (done) begin
                    verify(!busy && drive_en == 0, "done must release every output");
                    disable waiting;
                end
            end
            verify(0, "test completion timeout");
        end
    endtask

    task automatic compare_complete;
        begin
            verify(!aborted, "unexpected abort flag");
            verify(samples_ab == gold_goal && samples_ba == gold_goal, "full sample counts");
            verify(gold_samples[0] == gold_goal && gold_samples[1] == gold_goal, "gold sample counts");
            verify(errors_ab == gold_errors[0] && errors_ba == gold_errors[1], "error counts");
            verify(block_errors_ab == gold_max_block[0] && block_errors_ba == gold_max_block[1],
                "maximum 10000-sample block error counts");
            verify(status_ab == reference_status(0) && status_ba == reference_status(1), "status classification");
            $display("CASE_PASS core n=%0d pins=%0d/%0d mode=%0d fault=%0d samples=%0d/%0d errors=%0d/%0d max10k=%0d/%0d status=%0d/%0d",
                cases, harness_a+3, harness_b+3, gold_mode, fault,
                samples_ab, samples_ba, errors_ab, errors_ba,
                block_errors_ab, block_errors_ba, status_ab, status_ba);
            monitor_run = 0;
        end
    endtask

    task automatic complete_case(input integer a, input integer b, input integer m, input integer f);
        begin
            prepare(a,b,m,f,1);
            await_done(gold_goal * SYMBOL * 2 + GAP + 40);
            compare_complete();
        end
    endtask

    task automatic invalid_case(input integer a, input integer b, input integer m, input bit q);
        begin
            prepare(a,b,m,0,q);
            // Invalid requests may pulse done on the same edge as start.
            #1;
            verify(status_ab == INVALID && status_ba == INVALID, "invalid request status");
            verify(samples_ab == 0 && samples_ba == 0 && errors_ab == 0 && errors_ba == 0,
                "invalid request leaves zero counts");
            repeat (4) @(negedge clk);
            verify(!busy && drive_en == 0, "invalid request remains high-Z");
            $display("CASE_PASS core n=%0d rejected pins=%0d/%0d mode=%0d qualified=%0d",cases,a,b,m,q);
        end
    endtask

    task automatic do_abort(input integer phase);
        integer cycles;
        begin
            prepare(0,1,0,0,1);
            cycles = 0;
            if (phase == 0) begin
                // Abort during the first settle interval.
                repeat (2) @(negedge clk);
            end else if (phase == 1) begin
                while (samples_ab < 25 && cycles < 2000) begin
                    @(negedge clk); cycles = cycles + 1;
                end
            end else if (phase == 2) begin
                while (!(busy && samples_ab == 100 && drive_en == 0) && cycles < 2000) begin
                    @(negedge clk); cycles = cycles + 1;
                end
            end else begin
                while (samples_ba < 25 && cycles < 4000) begin
                    @(negedge clk); cycles = cycles + 1;
                end
            end
            verify(busy, "abort phase must be active");
            abort = 1;
            await_done(4);
            @(negedge clk); abort = 0;
            verify(aborted && status_ab == INVALID && status_ba == INVALID, "aborted results invalid");
            verify(samples_ab == gold_samples[0] && samples_ba == gold_samples[1], "abort preserves completed sample counts");
            verify(errors_ab == 0 && errors_ba == 0, "healthy aborted test error counts");
            verify(drive_en == 0, "abort releases output immediately");
            monitor_run = 0;
            $display("CASE_PASS core n=%0d abort_phase=%0d samples=%0d/%0d",cases,phase,samples_ab,samples_ba);
        end
    endtask

    integer pair, phase;
    initial begin
        for (s=0;s<2;s=s+1) begin
            gold_samples[s]=0; gold_errors[s]=0; gold_zeros[s]=0; gold_ones[s]=0;
            gold_block[s]=0; gold_max_block[s]=0; gold_lfsr[s]=16'h1ace;
        end
        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(4) @(negedge clk);
        verify(!busy && drive_en == 0, "idle starts high-Z");
        for (pair=0;pair<17;pair=pair+1) complete_case(pair*2,pair*2+1,0,0);
        complete_case(0,33,0,0);
        complete_case(7,25,0,0);
        complete_case(33,0,0,0);
        invalid_case(0,1,0,0);
        invalid_case(34,1,0,1);
        invalid_case(0,63,0,1);
        invalid_case(10,10,0,1);
        invalid_case(0,1,3,1);
        complete_case(0,1,0,1);
        complete_case(0,1,0,2);
        complete_case(0,1,0,3);
        complete_case(0,1,0,5);
        complete_case(0,1,0,4);
        complete_case(0,1,0,7);
        complete_case(0,1,0,8);
        // Running tests latch their configuration and ignore a further START.
        prepare(0,1,0,0,1);
        while(samples_ab < 20) @(negedge clk);
        pin_a=20; pin_b=20; mode=3; qualified=0; start=1;
        @(negedge clk); start=0;
        await_done(100*SYMBOL*2+GAP+40);
        compare_complete();
        // Full production sample counts; only symbol/settle/gap are accelerated.
        complete_case(2,3,1,0);
        complete_case(18,19,2,6);
        for (phase=0;phase<4;phase=phase+1) do_abort(phase);
        // Restart after abort, then abort plus start at idle must never drive.
        complete_case(0,1,0,0);
        @(negedge clk); abort=1; start=1;
        @(negedge clk); start=0; abort=0;
        #1; verify(drive_en == 0 && !busy, "start and abort priority");
        // Asynchronous reset while driving must immediately release the pins.
        prepare(0,1,0,0,1);
        repeat(3) @(negedge clk);
        #2; rst_n=0;
        #1; verify(drive_en == 0 && !busy, "asynchronous reset safety");
        monitor_run=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        complete_case(32,33,0,0);
        $display("TB_PASS gpio_core cases=%0d checks=%0d active_drive_cycles=%0d",cases,checks,drive_cycles);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "TB_FAIL gpio_core global timeout");
    end
endmodule
`default_nettype wire
