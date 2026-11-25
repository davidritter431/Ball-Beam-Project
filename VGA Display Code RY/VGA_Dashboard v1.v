// VGA_Dashboard.v
// Nexys A7-100T dashboard. Add as a Design Source in Vivado.
// Inputs are sampled in the clk100 domain; one history entry is stored
// whenever sample_valid pulses. VGA timing uses a 25 MHz pixel enable.
module VGA_Dashboard (
    input wire clk100,
    input wire reset,
    input wire sample_valid,
    input wire [15:0] distance_cm,
    input wire [15:0] target_cm,
    input wire signed [16:0] error_cm,
    input wire [31:0] pwm_command,
    output reg [3:0] vga_red,
    output reg [3:0] vga_green,
    output reg [3:0] vga_blue,
    output reg vga_hs,
    output reg vga_vs
);
    reg [1:0] pixel_div = 0;
    wire pixel_tick = (pixel_div == 2'd3);
    reg [9:0] pixel_x = 0, pixel_y = 0;
    wire active_video = (pixel_x < 640) && (pixel_y < 480);

    // Circular buffer: 256 most recent valid LiDAR measurements.
    reg [15:0] history [0:255];
    reg [7:0] write_ptr = 0;
    reg [8:0] sample_count = 0;
    integer i;
    always @(posedge clk100) begin
        if (reset) begin
            write_ptr <= 0;
            sample_count <= 0;
            for (i=0; i<256; i=i+1) history[i] <= 0;
        end else if (sample_valid) begin
            history[write_ptr] <= distance_cm;
            write_ptr <= write_ptr + 1'b1;
            if (sample_count < 256) sample_count <= sample_count + 1'b1;
        end
    end

    // 640x480 @ approximately 59.5 Hz: H total 800, V total 525.
    always @(posedge clk100) begin
        if (reset) begin
            pixel_div <= 0; pixel_x <= 0; pixel_y <= 0;
        end else begin
            pixel_div <= pixel_div + 1'b1;
            if (pixel_tick) begin
                if (pixel_x == 799) begin
                    pixel_x <= 0;
                    if (pixel_y == 524) pixel_y <= 0;
                    else pixel_y <= pixel_y + 1'b1;
                end else pixel_x <= pixel_x + 1'b1;
            end
        end
    end
    always @(*) begin
        vga_hs = !((pixel_x >= 656) && (pixel_x < 752));
        vga_vs = !((pixel_y >= 490) && (pixel_y < 492));
    end

    // Seven-segment numeric glyph, 40x64 pixels.
    function digit_pixel;
        input [3:0] digit;
        input [5:0] lx, ly;
        reg [6:0] s;
        begin
            case (digit)
                0:s=7'b1111110; 1:s=7'b0110000; 2:s=7'b1101101;
                3:s=7'b1111001; 4:s=7'b0110011; 5:s=7'b1011011;
                6:s=7'b1011111; 7:s=7'b1110000; 8:s=7'b1111111;
                9:s=7'b1111011; default:s=7'b0000001;
            endcase
            digit_pixel =
                (((ly < 6) && (lx >= 7) && (lx < 33)) && s[6]) ||
                (((ly >= 29) && (ly < 35) && (lx >= 7) && (lx < 33)) && s[3]) ||
                (((ly >= 58) && (lx >= 7) && (lx < 33)) && s[0]) ||
                (((lx < 6) && (ly >= 6) && (ly < 29)) && s[5]) ||
                (((lx >= 34) && (ly >= 6) && (ly < 29)) && s[4]) ||
                (((lx < 6) && (ly >= 35) && (ly < 58)) && s[1]) ||
                (((lx >= 34) && (ly >= 35) && (ly < 58)) && s[2]);
        end
    endfunction

    // 5x7 uppercase font used for compact KPI and graph labels.
    function [34:0] glyph5;
        input [7:0] ch;
        begin
            case (ch)
                "A": glyph5=35'b01110100011000111111100011000110001;
                "C": glyph5=35'b01111100001000010000100001000001111;
                "D": glyph5=35'b11110100011000110001100011000111110;
                "E": glyph5=35'b11111100001000011110100001000011111;
                "G": glyph5=35'b01111100001000010111100011000101111;
                "H": glyph5=35'b10001100011000111111100011000110001;
                "I": glyph5=35'b11111001000010000100001000010011111;
                "M": glyph5=35'b10001110111010110101100011000110001;
                "N": glyph5=35'b10001110011010110011100011000110001;
                "O": glyph5=35'b01110100011000110001100011000101110;
                "P": glyph5=35'b11110100011000111110100001000010000;
                "R": glyph5=35'b11110100011000111110101001001010001;
                "S": glyph5=35'b01111100001000001110000010000111110;
                "T": glyph5=35'b11111001000010000100001000010000100;
                "W": glyph5=35'b10001100011000110101101011010101010;
                "Y": glyph5=35'b10001100010101000100001000010000100;
                default: glyph5=35'd0;
            endcase
        end
    endfunction

    function label_pixel;
        input [2:0] label_id;
        input [6:0] lx;
        input [3:0] ly;
        reg [7:0] ch;
        reg [34:0] bits;
        reg [3:0] ci;
        reg [2:0] cx;
        begin
            ci=lx/6; cx=lx%6; ch=0;
            case(label_id)
                0: case(ci) // DISTANCE
                    0:ch="D"; 1:ch="I"; 2:ch="S"; 3:ch="T";
                    4:ch="A"; 5:ch="N"; 6:ch="C"; 7:ch="E";
                    default:ch=0;
                endcase
                1: case(ci) // TARGET
                    0:ch="T"; 1:ch="A"; 2:ch="R"; 3:ch="G";
                    4:ch="E"; 5:ch="T"; default:ch=0;
                endcase
                2: case(ci) // ERROR
                    0:ch="E"; 1:ch="R"; 2:ch="R"; 3:ch="O";
                    4:ch="R"; default:ch=0;
                endcase
                3: case(ci) // HISTORY
                    0:ch="H"; 1:ch="I"; 2:ch="S"; 3:ch="T";
                    4:ch="O"; 5:ch="R"; 6:ch="Y"; default:ch=0;
                endcase
                4: case(ci) // PWM
                    0:ch="P"; 1:ch="W"; 2:ch="M"; default:ch=0;
                endcase
                default:ch=0;
            endcase
            bits=glyph5(ch);
            if (ly<7 && cx<5 && ch!=0) label_pixel=bits[34-(ly*5+cx)];
            else label_pixel=1'b0;
        end
    endfunction

    wire [15:0] dist_v = (distance_cm > 999) ? 999 : distance_cm;
    wire [15:0] targ_v = (target_cm > 999) ? 999 : target_cm;
    wire [16:0] abs_err = error_cm[16] ? -error_cm : error_cm;
    wire [15:0] err_v = (abs_err > 999) ? 999 : abs_err;
    wire [3:0] dh=(dist_v/100)%10, dt=(dist_v/10)%10, do_=dist_v%10;
    wire [3:0] th=(targ_v/100)%10, tt=(targ_v/10)%10, to_=targ_v%10;
    wire [3:0] eh=(err_v/100)%10, et=(err_v/10)%10, eo=err_v%10;

    wire label_distance = pixel_x>=45 && pixel_x<93 && pixel_y>=57 && pixel_y<66 &&
                          label_pixel(0,pixel_x-45,pixel_y-57);
    wire label_target = pixel_x>=235 && pixel_x<271 && pixel_y>=57 && pixel_y<66 &&
                        label_pixel(1,pixel_x-235,pixel_y-57);
    wire label_error = pixel_x>=425 && pixel_x<455 && pixel_y>=57 && pixel_y<66 &&
                       label_pixel(2,pixel_x-425,pixel_y-57);
    wire label_history = pixel_x>=40 && pixel_x<82 && pixel_y>=174 && pixel_y<183 &&
                         label_pixel(3,pixel_x-40,pixel_y-174);
    wire label_pwm = pixel_x>=420 && pixel_x<438 && pixel_y>=430 && pixel_y<439 &&
                     label_pixel(4,pixel_x-420,pixel_y-430);

    // History graph: 144 samples displayed across 576 pixels.
    // Vertical scale: 0..100 cm, 2 pixels per cm.
    wire graph_area = (pixel_x>=32 && pixel_x<608 && pixel_y>=190 && pixel_y<414);
    wire [7:0] hist_index = write_ptr - 8'd144 + ((pixel_x-32) >> 2);
    wire [15:0] hist_value = history[hist_index];
    wire [7:0] hist_clamped = (hist_value>100) ? 100 : hist_value[7:0];
    wire [8:0] trace_y = 9'd413 - (hist_clamped << 1);
    wire [7:0] target_clamped = (target_cm>100) ? 100 : target_cm[7:0];
    wire [8:0] target_y = 9'd413 - (target_clamped << 1);
    wire grid_line = graph_area && (((pixel_y-190) % 40)==0);
    wire target_line = graph_area && (pixel_y>=target_y-2 && pixel_y<=target_y+2);
    wire trace_line = graph_area && sample_count!=0 &&
                      (pixel_y>=trace_y-2 && pixel_y<=trace_y+2);

    // Three numeric KPI groups, each with three 40x64 digits.
    wire digit_row = (pixel_y>=75 && pixel_y<139);
    wire current_digits = digit_row && (
        (pixel_x>=45 && pixel_x<85 && digit_pixel(dh,pixel_x-45,pixel_y-75)) ||
        (pixel_x>=85 && pixel_x<125 && digit_pixel(dt,pixel_x-85,pixel_y-75)) ||
        (pixel_x>=125 && pixel_x<165 && digit_pixel(do_,pixel_x-125,pixel_y-75)));
    wire target_digits = digit_row && (
        (pixel_x>=235 && pixel_x<275 && digit_pixel(th,pixel_x-235,pixel_y-75)) ||
        (pixel_x>=275 && pixel_x<315 && digit_pixel(tt,pixel_x-275,pixel_y-75)) ||
        (pixel_x>=315 && pixel_x<355 && digit_pixel(to_,pixel_x-315,pixel_y-75)));
    wire error_sign = error_cm[16] && digit_row && pixel_x>=385 && pixel_x<425 &&
                      digit_pixel(4'hF,pixel_x-385,pixel_y-75);
    wire error_digits = digit_row && (
        (pixel_x>=425 && pixel_x<465 && digit_pixel(eh,pixel_x-425,pixel_y-75)) ||
        (pixel_x>=465 && pixel_x<505 && digit_pixel(et,pixel_x-465,pixel_y-75)) ||
        (pixel_x>=505 && pixel_x<545 && digit_pixel(eo,pixel_x-505,pixel_y-75)));

    // PWM command bar, scaled from 100000..200000 counts.
    wire [31:0] pwm_clip = (pwm_command<100000) ? 100000 :
                           ((pwm_command>200000) ? 200000 : pwm_command);
    wire [8:0] pwm_pixels = (pwm_clip-100000)/556;
    wire pwm_box = pixel_x>=420 && pixel_x<608 && pixel_y>=445 && pixel_y<465;
    wire pwm_fill = pwm_box && pixel_x < (10'd424+pwm_pixels);

    wire frame_line = (pixel_y>=38 && pixel_y<41 && pixel_x>=24 && pixel_x<616) ||
                      (pixel_y>=150 && pixel_y<153 && pixel_x>=24 && pixel_x<616);
    wire graph_edge = graph_area && (pixel_x==32 || pixel_x==607 || pixel_y==190 || pixel_y==413);
    wire pwm_edge = ((pixel_x>=420 && pixel_x<608) && (pixel_y==445 || pixel_y==464)) ||
                    ((pixel_y>=445 && pixel_y<465) && (pixel_x==420 || pixel_x==607));
    wire legend_actual = pixel_x>=40 && pixel_x<58 && pixel_y>=166 && pixel_y<174;
    wire legend_target = pixel_x>=190 && pixel_x<208 && pixel_y>=166 && pixel_y<174;

    always @(*) begin
        vga_red=0; vga_green=0; vga_blue=0;
        if (active_video) begin
            // Dark navy dashboard background
            vga_red=0; vga_green=1; vga_blue=3;
            if (frame_line || graph_edge || pwm_edge) begin
                vga_red=2; vga_green=8; vga_blue=12;
            end
            if (label_distance || label_target || label_error || label_history || label_pwm) begin
                vga_red=8; vga_green=12; vga_blue=15;
            end
            if (current_digits || legend_actual) begin
                vga_red=0; vga_green=15; vga_blue=7;
            end
            if (target_digits || legend_target || target_line) begin
                vga_red=15; vga_green=10; vga_blue=2;
            end
            if (error_digits || error_sign) begin
                vga_red=15; vga_green=15; vga_blue=15;
            end
            if (grid_line) begin
                vga_red=1; vga_green=3; vga_blue=5;
            end
            if (trace_line) begin
                vga_red=0; vga_green=15; vga_blue=7;
            end
            if (pwm_box) begin
                vga_red=2; vga_green=3; vga_blue=5;
            end
            if (pwm_fill) begin
                vga_red=11; vga_green=3; vga_blue=15;
            end
        end
    end
endmodule
