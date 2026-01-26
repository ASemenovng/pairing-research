// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BigIntFp {
    // ============================================
    // BLS12-381 Base Field Parameters
    // ============================================
    
    // P = 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab
    
    // P[0]: Младшие 256 бит
    uint256 private constant P_LO  = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;
    // P[1]: Старшие 125 бит
    uint256 private constant P_HI  = 0x1a0111ea397fe69a4b1ba7b6434bacd7;

    // R^2 mod P (Необходимо для toMontgomery)
    uint256 private constant R2_LO = 0xcc0868ce6a76590c76e5bc3ff951c543861c23693de6a351fb73eaead26ebe58;
    uint256 private constant R2_HI = 0x10a8c1a49a064ff0a85a3f35446d0b;

    // μ = -P^(-1) mod 2^256 (Необходимо для редукции)
    uint256 private constant MAGIC = 0x19ecca0e8eb2db4c16ef2ef0c8e30b48286adb92d9d113e889f3fffcfffcfffd;

    // ============================================
    // Сложение (Add)
    // ============================================

    function add(uint256[2] memory a, uint256[2] memory b) internal pure returns (uint256[2] memory res) {
        assembly {
            let a0 := mload(a)
            let a1 := mload(add(a, 32))
            let b0 := mload(b)
            let b1 := mload(add(b, 32))
            
            let r0 := add(a0, b0)
            let carry := lt(r0, a0)
            let r1 := add(a1, b1)
            r1 := add(r1, carry)
            
            // Проверка: результат >= P?
            let ge := or(gt(r1, P_HI), and(eq(r1, P_HI), iszero(lt(r0, P_LO))))
            
            if ge {
                let r0_sub := sub(r0, P_LO)
                let borrow := gt(r0_sub, r0)
                r0 := r0_sub
                r1 := sub(r1, P_HI)
                r1 := sub(r1, borrow)
            }
            
            mstore(res, r0)
            mstore(add(res, 32), r1)
        }
    }
    
    // ============================================
    // Вычитание (Sub)
    // ============================================

    function sub(uint256[2] memory a, uint256[2] memory b) internal pure returns (uint256[2] memory res) {
        assembly {
            let a0 := mload(a)
            let a1 := mload(add(a, 32))
            let b0 := mload(b)
            let b1 := mload(add(b, 32))
            
            let r0 := sub(a0, b0)
            let borrow := gt(r0, a0)
            let r1 := sub(a1, b1)
            r1 := sub(r1, borrow)
            
            // Проверка на underflow
            let less := or(lt(a1, b1), and(eq(a1, b1), lt(a0, b0)))
            
            if less {
                let r0_add := add(r0, P_LO)
                let carry := lt(r0_add, r0)
                r0 := r0_add
                r1 := add(r1, P_HI)
                r1 := add(r1, carry)
            }
            mstore(res, r0)
            mstore(add(res, 32), r1)
        }
    }

    // ============================================
    // Уумножение Монтгомери (Stack Optimized)
    // ============================================

    function montMul(uint256[2] memory a, uint256[2] memory b) internal pure returns (uint256[2] memory res) {
        assembly {
             // Мы НЕ загружаем a0, a1, b0, b1 здесь, чтобы сэкономить 4 слота стека.
             // Мы будем загружать их по требованию (mload) внутри блоков.
             
             // Аккумулятор T (3 слова)
             let t0 := 0
             let t1 := 0
             let t2 := 0
             
             // --- LOOP 0 (Обработка a[0]) ---
             
             // 1. T += a[0] * b[0]
             {
                 let x := mload(a)         // Загружаем a[0]
                 let y := mload(b)         // Загружаем b[0]
                 
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1) 
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }

                 t0 := add(t0, lo)
                 let c := lt(t0, lo)
                 t1 := add(t1, hi)
                 t1 := add(t1, c)
                 if lt(t1, hi) { t2 := add(t2, 1) }
             } // x и y удаляются из стека здесь

             // T += a[0] * b[1]
             {
                 let x := mload(a)           // Снова a[0]
                 let y := mload(add(b, 32))  // Загружаем b[1]
                 
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1) 
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }

                 t1 := add(t1, lo)
                 let c := lt(t1, lo)
                 t2 := add(t2, hi)
                 t2 := add(t2, c)
             }
             
             // Редукция 0: m = t0 * MAGIC
             let m := mul(t0, MAGIC)
             
             // m * P_LO
             {
                 let x := m
                 let y := P_LO
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1)
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }

                 let sum_lo := add(t0, lo) 
                 let c := lt(sum_lo, t0) 
                 
                 t1 := add(t1, hi)
                 let c2 := lt(t1, hi)
                 t1 := add(t1, c) 
                 if lt(t1, c) { c2 := add(c2, 1) }
                 
                 t2 := add(t2, c2)
             }
             
             // m * P_HI
              {
                 let x := m
                 let y := P_HI
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1)
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }

                 t1 := add(t1, lo)
                 let c := lt(t1, lo)
                 t2 := add(t2, hi)
                 t2 := add(t2, c)
             }
             
             // Сдвиг
             t0 := t1
             t1 := t2
             t2 := 0
             
             // --- LOOP 1 (Обработка a[1]) ---
             
             // a[1] * b[0]
             {
                 let x := mload(add(a, 32)) // a[1]
                 let y := mload(b)          // b[0]
                 
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1)
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }
                 
                 t0 := add(t0, lo)
                 let c := lt(t0, lo)
                 t1 := add(t1, hi)
                 t1 := add(t1, c)
                 if lt(t1, hi) { t2 := add(t2, 1) }
             }
             
             // a[1] * b[1]
             {
                 let x := mload(add(a, 32)) // a[1]
                 let y := mload(add(b, 32)) // b[1]
                 
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1)
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }
                 
                 t1 := add(t1, lo)
                 let c := lt(t1, lo)
                 t2 := add(t2, hi)
                 t2 := add(t2, c)
             }
             
             // Редукция 1
             m := mul(t0, MAGIC)
             
             // m * P_LO
             {
                 let x := m
                 let y := P_LO
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1)
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }

                 let sum_lo := add(t0, lo) 
                 let c := lt(sum_lo, t0)
                 t1 := add(t1, hi)
                 let c2 := lt(t1, hi)
                 t1 := add(t1, c)
                 if lt(t1, c) { c2 := add(c2, 1) }
                 t2 := add(t2, c2)
             }
             
             // m * P_HI
              {
                 let x := m
                 let y := P_HI
                 let x_lo := and(x, 0xffffffffffffffffffffffffffffffff)
                 let x_hi := shr(128, x)
                 let y_lo := and(y, 0xffffffffffffffffffffffffffffffff)
                 let y_hi := shr(128, y)
                 let p0 := mul(x_lo, y_lo)
                 let p1 := mul(x_lo, y_hi)
                 let p2 := mul(x_hi, y_lo)
                 let p3 := mul(x_hi, y_hi)
                 let mid := add(p1, p2)
                 let mid_carry := lt(mid, p1)
                 let lo := add(p0, shl(128, mid))
                 let hi := add(add(p3, shr(128, mid)), shl(128, mid_carry))
                 if lt(lo, p0) { hi := add(hi, 1) }

                 t1 := add(t1, lo)
                 let c := lt(t1, lo)
                 t2 := add(t2, hi)
                 t2 := add(t2, c)
             }
             
             // Сдвиг
             t0 := t1
             t1 := t2
             t2 := 0
             
             // --- ФИНАЛ ---
             let ge := or(gt(t1, P_HI), and(eq(t1, P_HI), iszero(lt(t0, P_LO))))
             if ge {
                let r0_sub := sub(t0, P_LO)
                let borrow := gt(r0_sub, t0)
                t0 := r0_sub
                t1 := sub(t1, P_HI)
                t1 := sub(t1, borrow)
             }
             
             mstore(res, t0)
             mstore(add(res, 32), t1)
        }
    }

    
    function toMontgomery(uint256[2] memory x) internal pure returns (uint256[2] memory) {
        uint256[2] memory R2; 
        R2[0] = R2_LO; R2[1] = R2_HI;
        return montMul(x, R2);
    }
    
    function fromMontgomery(uint256[2] memory x) internal pure returns (uint256[2] memory) {
         uint256[2] memory ONE; 
         ONE[0] = 1; ONE[1] = 0;
         return montMul(x, ONE);
    }
}
