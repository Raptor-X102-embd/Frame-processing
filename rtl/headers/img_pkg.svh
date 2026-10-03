`ifndef IMG_PKG
`define IMG_PKG

package img_pkg;

    typedef struct {
        logic [7:0] R;
        logic [7:0] G;
        logic [7:0] B;
    } pixel_t;
    
    typedef struct {
        int N;
        int D;
    } fract_t;

endpackage

`endif
