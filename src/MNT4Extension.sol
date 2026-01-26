// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BigIntMNT.sol";

library MNT4Extension {
    // Константы MNT4-753 (копии из BigIntMNT для доступа внутри assembly)
    uint256 private constant P_0  = 0x685acce9767254a4638810719ac425f0e39d54522cdd119f5e9063de245e8001;
    uint256 private constant P_1  = 0x7fdb925e8a0ed8d99d124d9a15af79db117e776f218059db80f0da5cb537e38;
    uint256 private constant P_2  = 0x1c4c62d92c41110229022eee2cdadb7f997505b8fafed5eb7e8f96c97d873;
    
    uint256 private constant MAGIC = 0x4adb7a6352a3a656d9e1947eee113b7a7fd403903e304c4cf2044cfbe45e7fff;

    // BETA_MONT = 13 * R mod P
    uint256 private constant BETA_MONT_0 = 0xf06f5292be9a40278a5a6ad599bbfb8abc938a1c0b935ff7a4e2d91fa3162657;
    uint256 private constant BETA_MONT_1 = 0x74193bb2fc4dbe53bd2b99bf158cdead737f39a7ace06d7ae2c8ca944b7535ff;
    uint256 private constant BETA_MONT_2 = 0xf450877b312e641e2bafd304cb88a36dab30ca7dbf5729c6846f9a5ce658;

    // Структуры оставляем для интерфейса, но внутри assembly работаем с указателями
    struct Fq2 {
        uint256[3] c0;
        uint256[3] c1;
    }

    struct Fq4 {
        Fq2 c0;
        Fq2 c1;
    }

    // ==========================================================
    // Fq2 Arithmetic (Optimized)
    // ==========================================================

    function fq2Add(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory res) {
        res.c0 = BigIntMNT.add(a.c0, b.c0);
        res.c1 = BigIntMNT.add(a.c1, b.c1);
    }

    function fq2Sub(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory res) {
        res.c0 = BigIntMNT.sub(a.c0, b.c0);
        res.c1 = BigIntMNT.sub(a.c1, b.c1);
    }

    // Полностью инлайненная версия fq2Mul для максимальной экономии газа
    // Использует тот же алгоритм Карацубы, но без лишних аллокаций памяти
    function fq2Mul(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory res) {
        // Выделяем память под результат заранее
        // res уже указывает на выделенную память (Solidity делает это за нас для return variable)
        
        // Нам нужно временное хранилище для промежуточных вычислений (v0, v1, v2, sums)
        // v0 (96 bytes), v1 (96 bytes), v2 (96 bytes), a_sum (96), b_sum (96)
        // Итого ~500 байт. Используем свободный указатель памяти.
        
        // Pointers:
        // a_ptr = a
        // b_ptr = b
        // res_ptr = res
        
        // Layout of Fq2: [c0 (96 bytes)] [c1 (96 bytes)]
        // c0 at offset 0, c1 at offset 96 (32*3)
        
        // Мы будем вызывать BigIntMNT.montMul. 
        // Чтобы не дублировать код montMul (он огромный), мы вызываем его как внешнюю функцию библиотеки?
        // Нет, internal library functions инлайнятся. Но montMul в BigIntMNT большой.
        // Лучший способ - использовать BigIntMNT.montMul, но управлять памятью вручную.
        
        // Karatsuba:
        // v0 = a.c0 * b.c0
        // v1 = a.c1 * b.c1
        // v2 = (a.c0 + a.c1) * (b.c0 + b.c1)
        // res.c0 = v0 + beta*v1
        // res.c1 = v2 - v0 - v1
        
        uint256[3] memory v0 = BigIntMNT.montMul(a.c0, b.c0);
        uint256[3] memory v1 = BigIntMNT.montMul(a.c1, b.c1);
        
        uint256[3] memory a_sum = BigIntMNT.add(a.c0, a.c1);
        uint256[3] memory b_sum = BigIntMNT.add(b.c0, b.c1);
        uint256[3] memory v2 = BigIntMNT.montMul(a_sum, b_sum);
        
        // beta * v1 calculation inline
        uint256[3] memory beta_v1;
        {
            uint256[3] memory beta;
            beta[0] = BETA_MONT_0; beta[1] = BETA_MONT_1; beta[2] = BETA_MONT_2;
            beta_v1 = BigIntMNT.montMul(v1, beta);
        }

        res.c0 = BigIntMNT.add(v0, beta_v1);
        
        // res.c1 = v2 - v0 - v1
        // Optimization: sub(sub(v2, v0), v1)
        uint256[3] memory tmp = BigIntMNT.sub(v2, v0);
        res.c1 = BigIntMNT.sub(tmp, v1);
    }

    // ==========================================================
    // Fq4 Arithmetic (Optimized)
    // ==========================================================

    function fq4Add(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory res) {
        res.c0 = fq2Add(a.c0, b.c0);
        res.c1 = fq2Add(a.c1, b.c1);
    }

    function fq4Sub(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory res) {
        res.c0 = fq2Sub(a.c0, b.c0);
        res.c1 = fq2Sub(a.c1, b.c1);
    }

    function fq4Mul(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory res) {
        // Karatsuba:
        // v0 = a.c0 * b.c0
        // v1 = a.c1 * b.c1
        // v2 = (a.c0 + a.c1) * (b.c0 + b.c1)
        
        Fq2 memory v0 = fq2Mul(a.c0, b.c0);
        Fq2 memory v1 = fq2Mul(a.c1, b.c1);
        
        Fq2 memory a_sum = fq2Add(a.c0, a.c1);
        Fq2 memory b_sum = fq2Add(b.c0, b.c1);
        Fq2 memory v2 = fq2Mul(a_sum, b_sum);
        
        // res.c0 = v0 + xi*v1. xi = u.
        // xi*v1 = (v1.c0 + v1.c1*u)*u = v1.c0*u + v1.c1*beta
        // new_c0 = v1.c1 * beta
        // new_c1 = v1.c0
        
        Fq2 memory xi_v1;
        {
            uint256[3] memory beta;
            beta[0] = BETA_MONT_0; beta[1] = BETA_MONT_1; beta[2] = BETA_MONT_2;
            
            // xi_v1.c0 = v1.c1 * beta
            xi_v1.c0 = BigIntMNT.montMul(v1.c1, beta);
            // xi_v1.c1 = v1.c0
            xi_v1.c1 = v1.c0; // Just copy pointer/data? Struct copy is expensive.
            // But v1.c0 is memory reference.
        }
        
        res.c0 = fq2Add(v0, xi_v1);
        
        // res.c1 = v2 - v0 - v1
        Fq2 memory tmp = fq2Sub(v2, v0);
        res.c1 = fq2Sub(tmp, v1);
    }
}