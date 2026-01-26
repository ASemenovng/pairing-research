// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BigIntMNT {

    // MNT4-753 Constants (Corrected)
    uint256 private constant P_0  = 0x685acce9767254a4638810719ac425f0e39d54522cdd119f5e9063de245e8001;
    uint256 private constant P_1  = 0x7fdb925e8a0ed8d99d124d9a15af79db117e776f218059db80f0da5cb537e38;
    uint256 private constant P_2  = 0x1c4c62d92c41110229022eee2cdadb7f997505b8fafed5eb7e8f96c97d873;

    uint256 private constant R2_0 = 0xa896a656a0714c7da24bea56242b3507c7d9ff8e7df03c0a84717088cfd190c8;
    uint256 private constant R2_1 = 0xe03c79cac4f7ef07a8c86d4604a3b5972f47839ef88d7ce880a46659ff6f3ddf;
    uint256 private constant R2_2 = 0x2a33e89cb485b081f15bcbfdacaf8e4605754c3817232505daf1f4a81245;

    uint256 private constant MAGIC = 0x4adb7a6352a3a656d9e1947eee113b7a7fd403903e304c4cf2044cfbe45e7fff;
        
    function add(uint256[3] memory a, uint256[3] memory b) internal pure returns (uint256[3] memory res) {
        assembly {
            let a0 := mload(a)
            let a1 := mload(add(a, 32))
            let a2 := mload(add(a, 64))
            
            let b0 := mload(b)
            let b1 := mload(add(b, 32))
            let b2 := mload(add(b, 64))
            
            let r0 := add(a0, b0)
            let c := lt(r0, a0)
            
            let r1 := add(a1, b1)
            let c_new := lt(r1, a1)
            r1 := add(r1, c)
            if lt(r1, c) { c_new := add(c_new, 1) } 
            
            let r2 := add(a2, b2)
            r2 := add(r2, c_new)
            
            // Reduction check: if res >= P
            let ge := 0
            if gt(r2, P_2) { ge := 1 }
            if eq(r2, P_2) {
                if gt(r1, P_1) { ge := 1 }
                if eq(r1, P_1) {
                    if iszero(lt(r0, P_0)) { ge := 1 }
                }
            }
            
            if ge {
                let sub_val := sub(r0, P_0)
                let borrow := gt(sub_val, r0)
                r0 := sub_val
                
                let sub_val_1 := sub(r1, P_1)
                let borrow_1 := gt(sub_val_1, r1)
                r1 := sub(sub_val_1, borrow) 
                if lt(sub_val_1, borrow) { borrow_1 := add(borrow_1, 1) }

                r2 := sub(sub(r2, P_2), borrow_1)
            }
            
            mstore(res, r0)
            mstore(add(res, 32), r1)
            mstore(add(res, 64), r2)
        }
    }
    
    function sub(uint256[3] memory a, uint256[3] memory b) internal pure returns (uint256[3] memory res) {
        assembly {
            let a0 := mload(a)
            let a1 := mload(add(a, 32))
            let a2 := mload(add(a, 64))
            
            let b0 := mload(b)
            let b1 := mload(add(b, 32))
            let b2 := mload(add(b, 64))
            
            let less := 0
            if lt(a2, b2) { less := 1 }
            if eq(a2, b2) {
                if lt(a1, b1) { less := 1 }
                if eq(a1, b1) {
                    if lt(a0, b0) { less := 1 }
                }
            }
            
            if less {
                let sum0 := add(a0, P_0)
                let c := lt(sum0, a0)
                a0 := sum0
                
                let sum1 := add(a1, P_1)
                let c_next := lt(sum1, a1)
                a1 := add(sum1, c)
                if lt(a1, c) { c_next := add(c_next, 1) }
                
                a2 := add(add(a2, P_2), c_next)
            }
            
            let r0 := sub(a0, b0)
            let br0 := gt(b0, a0) 
            
            let r1 := sub(a1, b1)
            let br1 := gt(b1, a1)
            let r1_new := sub(r1, br0)
            if lt(r1, br0) { br1 := add(br1, 1) }
            r1 := r1_new
            
            let r2 := sub(sub(a2, b2), br1)
            
            mstore(res, r0)
            mstore(add(res, 32), r1)
            mstore(add(res, 64), r2)
        }
    }

    function montMul(uint256[3] memory a, uint256[3] memory b) internal pure returns (uint256[3] memory res) {
        assembly {
            // Внутренняя функция для умножения 256x256 -> 512
            // Это решает проблему Stack Too Deep, так как переменные внутри функции
            // очищаются после возврата.
            function mul512(u, v) -> lo, hi {
                let p0 := mul(u, v)
                let u_lo := and(u, 0xffffffffffffffffffffffffffffffff)
                let u_hi := shr(128, u)
                let v_lo := and(v, 0xffffffffffffffffffffffffffffffff)
                let v_hi := shr(128, v)
                let m1 := mul(u_lo, v_hi)
                let m2 := mul(u_hi, v_lo)
                let mid := add(m1, m2)
                
                // hi = u_hi*v_hi + (mid >> 128) + ((mid < m1) << 128) + (p0 < u_lo*v_lo)
                let hi_temp := add(mul(u_hi, v_hi), shr(128, mid))
                hi_temp := add(hi_temp, shl(128, lt(mid, m1)))
                if lt(p0, mul(u_lo, v_lo)) { hi_temp := add(hi_temp, 1) }
                
                lo := p0
                hi := hi_temp
            }

            // Аккумулятор: t0, t1, t2, t3
            let t0 := 0
            let t1 := 0
            let t2 := 0
            let t3 := 0 
            
            // ================= LOOP 0 (a[0]) =================
            {
                let u_val := mload(a)
                
                // j=0
                {
                    let lo, hi := mul512(u_val, mload(b))
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                }
                // j=1
                {
                    let lo, hi := mul512(u_val, mload(add(b, 32)))
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                // j=2
                {
                    let lo, hi := mul512(u_val, mload(add(b, 64)))
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }
            
            // === REDUCTION 0 ===
            {
                let m := mul(t0, MAGIC)
                
                // j=0
                {
                    let lo, hi := mul512(m, P_0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                // j=1
                {
                    let lo, hi := mul512(m, P_1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                // j=2
                {
                    let lo, hi := mul512(m, P_2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }
            
            // Shift
            t0 := t1
            t1 := t2
            t2 := t3
            t3 := 0
            
            // ================= LOOP 1 (a[1]) =================
            {
                let u_val := mload(add(a, 32))
                
                // j=0
                {
                    let lo, hi := mul512(u_val, mload(b))
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                // j=1
                {
                    let lo, hi := mul512(u_val, mload(add(b, 32)))
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                // j=2
                {
                    let lo, hi := mul512(u_val, mload(add(b, 64)))
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }
            
            // === REDUCTION 1 ===
            {
                let m := mul(t0, MAGIC)
                
                // j=0
                {
                    let lo, hi := mul512(m, P_0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                // j=1
                {
                    let lo, hi := mul512(m, P_1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                // j=2
                {
                    let lo, hi := mul512(m, P_2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }
            
            // Shift
            t0 := t1
            t1 := t2
            t2 := t3
            t3 := 0
            
            // ================= LOOP 2 (a[2]) =================
            {
                let u_val := mload(add(a, 64))
                
                // j=0
                {
                    let lo, hi := mul512(u_val, mload(b))
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                // j=1
                {
                    let lo, hi := mul512(u_val, mload(add(b, 32)))
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                // j=2
                {
                    let lo, hi := mul512(u_val, mload(add(b, 64)))
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }
            
            // === REDUCTION 2 ===
            {
                let m := mul(t0, MAGIC)
                
                // j=0
                {
                    let lo, hi := mul512(m, P_0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                // j=1
                {
                    let lo, hi := mul512(m, P_1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                // j=2
                {
                    let lo, hi := mul512(m, P_2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }
            
            // Shift
            t0 := t1
            t1 := t2
            t2 := t3
            
            // --- Final Check ---
            let ge := 0
            if gt(t2, P_2) { ge := 1 }
            if eq(t2, P_2) {
                if gt(t1, P_1) { ge := 1 }
                if eq(t1, P_1) {
                    if iszero(lt(t0, P_0)) { ge := 1 }
                }
            }
            
            if ge {
                let r0 := sub(t0, P_0)
                let bor := gt(r0, t0)
                t0 := r0
                
                let r1 := sub(t1, P_1)
                let bor1 := gt(r1, t1)
                let t1_sub := sub(r1, bor)
                if lt(r1, bor) { bor1 := add(bor1, 1) }
                t1 := t1_sub
                
                let r2 := sub(t2, P_2)
                t2 := sub(r2, bor1)
            }
            
            mstore(res, t0)
            mstore(add(res, 32), t1)
            mstore(add(res, 64), t2)
        }
    }

    function toMontgomery(uint256[3] memory x) internal pure returns (uint256[3] memory) {
        uint256[3] memory R2; 
        R2[0] = R2_0; R2[1] = R2_1; R2[2] = R2_2;
        return montMul(x, R2);
    }
    
    function fromMontgomery(uint256[3] memory x) internal pure returns (uint256[3] memory) {
         uint256[3] memory ONE; 
         ONE[0] = 1; ONE[1] = 0; ONE[2] = 0;
         return montMul(x, ONE);
    }
}