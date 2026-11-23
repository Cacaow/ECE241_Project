module jump_calc (
    input  wire        clk,
    input  wire [9:0]  angle,      // 0 to 180 degrees
    input  wire [9:0]  dist,       // jump distance in pixels
    output reg  [9:0]  dx_mag,     // |dist * cos(angle)|
    output reg         dx_side,     // 1 = move LEFT (angle > 90), 0 = move RIGHT
    output reg  [9:0]  dy_mag      // dist * sin(angle), move UP by this many pixels
);

    // 256 * sin(deg), deg = 0 to 90
    function [8:0] sin_q8;
        input [6:0] deg;
        begin
            case (deg)
                7'd0: sin_q8 = 9'd0;
                7'd1: sin_q8 = 9'd4;
                7'd2: sin_q8 = 9'd9;
                7'd3: sin_q8 = 9'd13;
                7'd4: sin_q8 = 9'd18;
                7'd5: sin_q8 = 9'd22;
                7'd6: sin_q8 = 9'd27;
                7'd7: sin_q8 = 9'd31;
                7'd8: sin_q8 = 9'd36;
                7'd9: sin_q8 = 9'd40;
                7'd10: sin_q8 = 9'd44;
                7'd11: sin_q8 = 9'd49;
                7'd12: sin_q8 = 9'd53;
                7'd13: sin_q8 = 9'd58;
                7'd14: sin_q8 = 9'd62;
                7'd15: sin_q8 = 9'd66;
                7'd16: sin_q8 = 9'd71;
                7'd17: sin_q8 = 9'd75;
                7'd18: sin_q8 = 9'd79;
                7'd19: sin_q8 = 9'd83;
                7'd20: sin_q8 = 9'd88;
                7'd21: sin_q8 = 9'd92;
                7'd22: sin_q8 = 9'd96;
                7'd23: sin_q8 = 9'd100;
                7'd24: sin_q8 = 9'd104;
                7'd25: sin_q8 = 9'd108;
                7'd26: sin_q8 = 9'd112;
                7'd27: sin_q8 = 9'd116;
                7'd28: sin_q8 = 9'd120;
                7'd29: sin_q8 = 9'd124;
                7'd30: sin_q8 = 9'd128;
                7'd31: sin_q8 = 9'd132;
                7'd32: sin_q8 = 9'd136;
                7'd33: sin_q8 = 9'd139;
                7'd34: sin_q8 = 9'd143;
                7'd35: sin_q8 = 9'd147;
                7'd36: sin_q8 = 9'd150;
                7'd37: sin_q8 = 9'd154;
                7'd38: sin_q8 = 9'd158;
                7'd39: sin_q8 = 9'd161;
                7'd40: sin_q8 = 9'd165;
                7'd41: sin_q8 = 9'd168;
                7'd42: sin_q8 = 9'd171;
                7'd43: sin_q8 = 9'd175;
                7'd44: sin_q8 = 9'd178;
                7'd45: sin_q8 = 9'd181;
                7'd46: sin_q8 = 9'd184;
                7'd47: sin_q8 = 9'd187;
                7'd48: sin_q8 = 9'd190;
                7'd49: sin_q8 = 9'd193;
                7'd50: sin_q8 = 9'd196;
                7'd51: sin_q8 = 9'd199;
                7'd52: sin_q8 = 9'd202;
                7'd53: sin_q8 = 9'd204;
                7'd54: sin_q8 = 9'd207;
                7'd55: sin_q8 = 9'd210;
                7'd56: sin_q8 = 9'd212;
                7'd57: sin_q8 = 9'd215;
                7'd58: sin_q8 = 9'd217;
                7'd59: sin_q8 = 9'd219;
                7'd60: sin_q8 = 9'd222;
                7'd61: sin_q8 = 9'd224;
                7'd62: sin_q8 = 9'd226;
                7'd63: sin_q8 = 9'd228;
                7'd64: sin_q8 = 9'd230;
                7'd65: sin_q8 = 9'd232;
                7'd66: sin_q8 = 9'd234;
                7'd67: sin_q8 = 9'd236;
                7'd68: sin_q8 = 9'd237;
                7'd69: sin_q8 = 9'd239;
                7'd70: sin_q8 = 9'd241;
                7'd71: sin_q8 = 9'd242;
                7'd72: sin_q8 = 9'd243;
                7'd73: sin_q8 = 9'd245;
                7'd74: sin_q8 = 9'd246;
                7'd75: sin_q8 = 9'd247;
                7'd76: sin_q8 = 9'd248;
                7'd77: sin_q8 = 9'd249;
                7'd78: sin_q8 = 9'd250;
                7'd79: sin_q8 = 9'd251;
                7'd80: sin_q8 = 9'd252;
                7'd81: sin_q8 = 9'd253;
                7'd82: sin_q8 = 9'd254;
                7'd83: sin_q8 = 9'd254;
                7'd84: sin_q8 = 9'd255;
                7'd85: sin_q8 = 9'd255;
                7'd86: sin_q8 = 9'd255;
                7'd87: sin_q8 = 9'd256;
                7'd88: sin_q8 = 9'd256;
                7'd89: sin_q8 = 9'd256;
                7'd90: sin_q8 = 9'd256;
                default: sin_q8 = 9'd256;
            endcase
        end
    endfunction

    wire [7:0] ang    = (angle > 10'd180) ? 8'd180 : angle[7:0];
    wire       over90 = (ang > 8'd90);

    wire [7:0] sin_idx = over90 ? (8'd180 - ang) : ang;             // 0 to 90
    wire [7:0] cos_idx = over90 ? (ang - 8'd90)  : (8'd90 - ang);   // 0 to 90

    wire [8:0] sin_q = sin_q8(sin_idx[6:0]);                         // 0 to 256
    wire [8:0] cos_q = sin_q8(cos_idx[6:0]);                         // 0 to 256

    wire [18:0] dx_full = dist * cos_q + 19'd128;                    // +128 = round to nearest
    wire [18:0] dy_full = dist * sin_q + 19'd128;

    always @(posedge clk) begin
        dx_mag <= dx_full[17:8];                                     // divide by 256
        dx_side <= over90;
        dy_mag <= dy_full[17:8];
    end

endmodule

`default_nettype wire