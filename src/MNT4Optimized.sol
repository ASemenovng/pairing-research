// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library MNT4Optimized {
    // MNT4-753 Modulus P
    // P = 0x1c4c62d92c41110229022eee2cdadb7f997505b8fafed5eb7e8f96c97d87307fdb925e8a0ed8d99d124d9a15af79db117e776f218059db80f0da5cb537e38685acce9767254a4638810719ac425f0e39d54522cdd119f5e9063de245e8001
    uint256 constant P0 = 0x685acce9767254a4638810719ac425f0e39d54522cdd119f5e9063de245e8001;
    uint256 constant P1 = 0x7fdb925e8a0ed8d99d124d9a15af79db117e776f218059db80f0da5cb537e38;
    uint256 constant P2 = 0x1c4c62d92c41110229022eee2cdadb7f997505b8fafed5eb7e8f96c97d873; // Fixed: added missing '3' at the end

    // Montgomery Magic Constant: -P^-1 mod 2^256
    uint256 constant MAGIC = 0x4adb7a6352a3a656d9e1947eee113b7a7fd403903e304c4cf2044cfbe45e7fff;

    // BETA = 13 * R mod P
    uint256 constant BETA_0 = 0xf06f5292be9a40278a5a6ad599bbfb8abc938a1c0b935ff7a4e2d91fa3162657;
    uint256 constant BETA_1 = 0x74193bb2fc4dbe53bd2b99bf158cdead737f39a7ace06d7ae2c8ca944b7535ff;
    uint256 constant BETA_2 = 0xf450877b312e641e2bafd304cb88a36dab30ca7dbf5729c6846f9a5ce658;

    struct Fq2 {
        uint256[3] c0;
        uint256[3] c1;
    }

    struct Fq4 {
        Fq2 c0;
        Fq2 c1;
    }

    // --- Internal Assembly Helpers ---

    // Montgomery Multiplication: z = x * y * R^-1 mod P
    function _montMul(uint256 z_ptr, uint256 x_ptr, uint256 y_ptr) internal pure {
        assembly {
            // Accumulator
            let t0 := 0
            let t1 := 0
            let t2 := 0
            let t3 := 0 // Carry limb

            for { let i := 0 } lt(i, 3) { i := add(i, 1) } {
                // Load x[i]
                let u := mload(add(x_ptr, mul(i, 0x20)))
                
                // --- Inner Loop over y ---
                // y0
                {
                    let v := mload(y_ptr)
                    // mul512(u, v) -> lo, hi
                    let u0 := and(u, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let u1 := shr(128, u)
                    let v0 := and(v, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let v1 := shr(128, v)
                    let w0 := mul(u0, v0)
                    let w1 := mul(u0, v1)
                    let w2 := mul(u1, v0)
                    let w3 := mul(u1, v1)
                    let mid := add(w1, w2)
                    let lo := add(w0, shl(128, mid))
                    let hi := add(add(w3, shr(128, mid)), add(shl(128, lt(mid, w1)), lt(lo, w0)))
                    
                    // Add to accumulator
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                }
                
                // y1
                {
                    let v := mload(add(y_ptr, 0x20))
                    let u0 := and(u, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let u1 := shr(128, u)
                    let v0 := and(v, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let v1 := shr(128, v)
                    let w0 := mul(u0, v0)
                    let w1 := mul(u0, v1)
                    let w2 := mul(u1, v0)
                    let w3 := mul(u1, v1)
                    let mid := add(w1, w2)
                    let lo := add(w0, shl(128, mid))
                    let hi := add(add(w3, shr(128, mid)), add(shl(128, lt(mid, w1)), lt(lo, w0)))
                    
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }

                // y2
                {
                    let v := mload(add(y_ptr, 0x40))
                    let u0 := and(u, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let u1 := shr(128, u)
                    let v0 := and(v, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let v1 := shr(128, v)
                    let w0 := mul(u0, v0)
                    let w1 := mul(u0, v1)
                    let w2 := mul(u1, v0)
                    let w3 := mul(u1, v1)
                    let mid := add(w1, w2)
                    let lo := add(w0, shl(128, mid))
                    let hi := add(add(w3, shr(128, mid)), add(shl(128, lt(mid, w1)), lt(lo, w0)))
                    
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }

                // --- Montgomery Reduction ---
                let m := mul(t0, MAGIC)
                
                // P0
                {
                    let v := P0
                    let u0 := and(m, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let u1 := shr(128, m)
                    let v0 := and(v, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let v1 := shr(128, v)
                    let w0 := mul(u0, v0)
                    let w1 := mul(u0, v1)
                    let w2 := mul(u1, v0)
                    let w3 := mul(u1, v1)
                    let mid := add(w1, w2)
                    let lo := add(w0, shl(128, mid))
                    let hi := add(add(w3, shr(128, mid)), add(shl(128, lt(mid, w1)), lt(lo, w0)))
                    
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                
                // P1
                {
                    let v := P1
                    let u0 := and(m, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let u1 := shr(128, m)
                    let v0 := and(v, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let v1 := shr(128, v)
                    let w0 := mul(u0, v0)
                    let w1 := mul(u0, v1)
                    let w2 := mul(u1, v0)
                    let w3 := mul(u1, v1)
                    let mid := add(w1, w2)
                    let lo := add(w0, shl(128, mid))
                    let hi := add(add(w3, shr(128, mid)), add(shl(128, lt(mid, w1)), lt(lo, w0)))
                    
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                
                // P2
                {
                    let v := P2
                    let u0 := and(m, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let u1 := shr(128, m)
                    let v0 := and(v, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                    let v1 := shr(128, v)
                    let w0 := mul(u0, v0)
                    let w1 := mul(u0, v1)
                    let w2 := mul(u1, v0)
                    let w3 := mul(u1, v1)
                    let mid := add(w1, w2)
                    let lo := add(w0, shl(128, mid))
                    let hi := add(add(w3, shr(128, mid)), add(shl(128, lt(mid, w1)), lt(lo, w0)))
                    
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
                
                // Shift
                t0 := t1
                t1 := t2
                t2 := t3
                t3 := 0
            }
            
            // --- Final Check ---
            let ge := 0
            if gt(t2, P2) { ge := 1 }
            if eq(t2, P2) {
                if gt(t1, P1) { ge := 1 }
                if eq(t1, P1) {
                    if or(gt(t0, P0), eq(t0, P0)) { ge := 1 }
                }
            }
            
            if ge {
                let r0 := sub(t0, P0)
                let bor := gt(r0, t0)
                t0 := r0
                
                let r1 := sub(t1, P1)
                let bor1 := gt(r1, t1)
                let t1_sub := sub(r1, bor)
                if lt(r1, bor) { bor1 := add(bor1, 1) }
                t1 := t1_sub
                
                let r2 := sub(t2, P2)
                t2 := sub(r2, bor1)
            }
            
            mstore(z_ptr, t0)
            mstore(add(z_ptr, 0x20), t1)
            mstore(add(z_ptr, 0x40), t2)
        }
    }

    // z = x + y mod P
    function _montAdd(uint256 z_ptr, uint256 x_ptr, uint256 y_ptr) internal pure {
        assembly {
            let x0 := mload(x_ptr)
            let x1 := mload(add(x_ptr, 0x20))
            let x2 := mload(add(x_ptr, 0x40))

            let y0 := mload(y_ptr)
            let y1 := mload(add(y_ptr, 0x20))
            let y2 := mload(add(y_ptr, 0x40))

            let r0 := add(x0, y0)
            let c0 := lt(r0, x0)
            
            let r1 := add(add(x1, y1), c0)
            let sum1 := add(x1, y1)
            let c1 := or(lt(sum1, x1), lt(r1, sum1))
            
            let r2 := add(add(x2, y2), c1)
            let c2 := or(lt(add(x2, y2), x2), lt(r2, add(x2, y2)))

            let ge := c2
            if iszero(ge) {
                if gt(r2, P2) { ge := 1 }
                if eq(r2, P2) {
                    if gt(r1, P1) { ge := 1 }
                    if eq(r1, P1) {
                        if or(gt(r0, P0), eq(r0, P0)) { ge := 1 }
                    }
                }
            }

            if ge {
                let diff0 := sub(r0, P0)
                let b0 := gt(diff0, r0)
                r0 := diff0
                
                let diff1 := sub(sub(r1, P1), b0)
                let b1 := or(lt(r1, P1), and(eq(r1, P1), b0))
                r1 := diff1
                
                let diff2 := sub(sub(r2, P2), b1)
                r2 := diff2
            }

            mstore(z_ptr, r0)
            mstore(add(z_ptr, 0x20), r1)
            mstore(add(z_ptr, 0x40), r2)
        }
    }

    // z = x - y mod P
    function _montSub(uint256 z_ptr, uint256 x_ptr, uint256 y_ptr) internal pure {
        assembly {
            let x0 := mload(x_ptr)
            let x1 := mload(add(x_ptr, 0x20))
            let x2 := mload(add(x_ptr, 0x40))

            let y0 := mload(y_ptr)
            let y1 := mload(add(y_ptr, 0x20))
            let y2 := mload(add(y_ptr, 0x40))

            let r0 := sub(x0, y0)
            let b0 := gt(r0, x0)

            let r1 := sub(sub(x1, y1), b0)
            let b1 := or(lt(x1, y1), and(eq(x1, y1), b0))

            let r2 := sub(sub(x2, y2), b1)
            let b2 := or(lt(x2, y2), and(eq(x2, y2), b1))

            if b2 {
                let sum0 := add(r0, P0)
                let c0 := lt(sum0, r0)
                r0 := sum0
                
                let sum1 := add(add(r1, P1), c0)
                let c1 := or(lt(add(r1, P1), r1), lt(sum1, add(r1, P1)))
                r1 := sum1
                
                let sum2 := add(add(r2, P2), c1)
                r2 := sum2
            }

            mstore(z_ptr, r0)
            mstore(add(z_ptr, 0x20), r1)
            mstore(add(z_ptr, 0x40), r2)
        }
    }

    // --- Fq2 Operations ---
    function fq2Add(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory res) {
        assembly {
            res := mload(0x40)
            mstore(0x40, add(res, 0xC0))
        }
        _montAdd(getPtr(res), getPtr(a), getPtr(b));
        _montAdd(getPtr(res) + 0x60, getPtr(a) + 0x60, getPtr(b) + 0x60);
    }

    function fq2Sub(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory res) {
        assembly {
            res := mload(0x40)
            mstore(0x40, add(res, 0xC0))
        }
        _montSub(getPtr(res), getPtr(a), getPtr(b));
        _montSub(getPtr(res) + 0x60, getPtr(a) + 0x60, getPtr(b) + 0x60);
    }

    function fq2Mul(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory res) {
        assembly {
            res := mload(0x40)
            mstore(0x40, add(res, 0xC0))
        }
        
        uint256 ptr_v0;
        uint256 ptr_v1;
        uint256 ptr_t;
        
        assembly {
            let fmp := mload(0x40)
            ptr_v0 := fmp
            ptr_v1 := add(fmp, 0x60)
            ptr_t := add(fmp, 0xC0)
            mstore(0x40, add(fmp, 0x120))
        }

        uint256 a_c0 = getPtr(a);
        uint256 a_c1 = a_c0 + 0x60;
        uint256 b_c0 = getPtr(b);
        uint256 b_c1 = b_c0 + 0x60;
        uint256 res_c0 = getPtr(res);
        uint256 res_c1 = res_c0 + 0x60;

        _montMul(ptr_v0, a_c0, b_c0);
        _montMul(ptr_v1, a_c1, b_c1);

        _montAdd(ptr_t, a_c0, a_c1);
        _montAdd(res_c1, b_c0, b_c1);
        _montMul(res_c1, ptr_t, res_c1);
        _montSub(res_c1, res_c1, ptr_v0);
        _montSub(res_c1, res_c1, ptr_v1);

        _montMul(ptr_t, ptr_v1, getPtrBetaConstant());
        _montAdd(res_c0, ptr_v0, ptr_t);
    }

    // --- Fq4 Operations ---
    function fq4Add(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory res) {
        assembly {
            res := mload(0x40)
            mstore(0x40, add(res, 0x180))
        }
        uint256 ptr_a = getPtr(a);
        uint256 ptr_b = getPtr(b);
        uint256 ptr_res = getPtr(res);
        
        _fq2AddPtr(ptr_res, ptr_a, ptr_b);
        _fq2AddPtr(ptr_res + 0xC0, ptr_a + 0xC0, ptr_b + 0xC0);
    }

    function fq4Sub(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory res) {
        assembly {
            res := mload(0x40)
            mstore(0x40, add(res, 0x180))
        }
        uint256 ptr_a = getPtr(a);
        uint256 ptr_b = getPtr(b);
        uint256 ptr_res = getPtr(res);

        _fq2SubPtr(ptr_res, ptr_a, ptr_b);
        _fq2SubPtr(ptr_res + 0xC0, ptr_a + 0xC0, ptr_b + 0xC0);
    }

    function fq4Mul(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory res) {
        assembly {
            res := mload(0x40)
            mstore(0x40, add(res, 0x180))
        }
        
        uint256 ptr_v0;
        uint256 ptr_v1;
        uint256 ptr_t_fq2;
        
        assembly {
            let fmp := mload(0x40)
            ptr_v0 := fmp
            ptr_v1 := add(fmp, 0xC0)
            ptr_t_fq2 := add(fmp, 0x180)
            mstore(0x40, add(fmp, 0x240))
        }
        
        uint256 a_c0 = getPtr(a);
        uint256 a_c1 = a_c0 + 0xC0;
        uint256 b_c0 = getPtr(b);
        uint256 b_c1 = b_c0 + 0xC0;
        uint256 res_c0 = getPtr(res);
        uint256 res_c1 = res_c0 + 0xC0;

        _fq2MulPtr(ptr_v0, a_c0, b_c0);
        _fq2MulPtr(ptr_v1, a_c1, b_c1);
        
        _fq2AddPtr(ptr_t_fq2, a_c0, a_c1);
        _fq2AddPtr(res_c1, b_c0, b_c1);
        _fq2MulPtr(res_c1, ptr_t_fq2, res_c1);
        _fq2SubPtr(res_c1, res_c1, ptr_v0);
        _fq2SubPtr(res_c1, res_c1, ptr_v1);
        
        _fq2MulByUPtr(ptr_t_fq2, ptr_v1);
        _fq2AddPtr(res_c0, ptr_v0, ptr_t_fq2);
    }

    // --- Helper Pointers & Constants ---

    function getPtr(Fq2 memory x) internal pure returns (uint256 ptr) {
        assembly { ptr := x }
    }
    
    function getPtr(Fq4 memory x) internal pure returns (uint256 ptr) {
        assembly { ptr := x }
    }

    function getPtrBetaConstant() internal pure returns (uint256 ptr) {
        assembly {
            let fmp := mload(0x40)
            mstore(fmp, BETA_0)
            mstore(add(fmp, 0x20), BETA_1)
            mstore(add(fmp, 0x40), BETA_2)
            ptr := fmp
            mstore(0x40, add(fmp, 0x60))
        }
    }

    // --- Fq2 Ptr Helpers ---
    
    function _fq2AddPtr(uint256 z, uint256 x, uint256 y) internal pure {
        _montAdd(z, x, y);
        _montAdd(z + 0x60, x + 0x60, y + 0x60);
    }
    
    function _fq2SubPtr(uint256 z, uint256 x, uint256 y) internal pure {
        _montSub(z, x, y);
        _montSub(z + 0x60, x + 0x60, y + 0x60);
    }
    
    function _fq2MulPtr(uint256 z, uint256 x, uint256 y) internal pure {
        uint256 ptr_v0;
        uint256 ptr_v1;
        uint256 ptr_t;
        assembly {
            let fmp := mload(0x40)
            ptr_v0 := fmp
            ptr_v1 := add(fmp, 0x60)
            ptr_t := add(fmp, 0xC0)
            mstore(0x40, add(fmp, 0x120))
        }
        
        _montMul(ptr_v0, x, y);
        _montMul(ptr_v1, x + 0x60, y + 0x60);
        
        _montAdd(ptr_t, x, x + 0x60);
        _montAdd(z + 0x60, y, y + 0x60);
        _montMul(z + 0x60, ptr_t, z + 0x60);
        _montSub(z + 0x60, z + 0x60, ptr_v0);
        _montSub(z + 0x60, z + 0x60, ptr_v1);
        
        _montMul(ptr_t, ptr_v1, getPtrBetaConstant());
        _montAdd(z, ptr_v0, ptr_t);
    }
    
    function _fq2MulByUPtr(uint256 z, uint256 x) internal pure {
        _montMul(z, x + 0x60, getPtrBetaConstant());
        
        assembly {
            let x0 := mload(x)
            let x1 := mload(add(x, 0x20))
            let x2 := mload(add(x, 0x40))
            mstore(add(z, 0x60), x0)
            mstore(add(z, 0x80), x1)
            mstore(add(z, 0xA0), x2)
        }
    }
}