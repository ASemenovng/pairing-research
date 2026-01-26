// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BigIntFp.sol";

// Обёртка для теста internal функций
contract BigIntHarness {
    function add(uint256[2] memory a, uint256[2] memory b) external pure returns (uint256[2] memory) {
        return BigIntFp.add(a, b);
    }
    function sub(uint256[2] memory a, uint256[2] memory b) external pure returns (uint256[2] memory) {
        return BigIntFp.sub(a, b);
    }
    function montMul(uint256[2] memory a, uint256[2] memory b) external pure returns (uint256[2] memory) {
        return BigIntFp.montMul(a, b);
    }
    function toMontgomery(uint256[2] memory x) external pure returns (uint256[2] memory) {
        return BigIntFp.toMontgomery(x);
    }
    function fromMontgomery(uint256[2] memory x) external pure returns (uint256[2] memory) {
        return BigIntFp.fromMontgomery(x);
    }
}

contract BigIntTest is Test {
    BigIntHarness lib;
    
    // Модуль BLS12-381 для проверок
    uint256 constant P_LO  = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;
    uint256 constant P_HI  = 0x1a0111ea397fe69a4b1ba7b6434bacd7;

    function setUp() public {
        lib = new BigIntHarness();
    }

    // Хелпер: создать число из одного uint256
    function mk(uint256 x) internal pure returns (uint256[2] memory r) {
        r[0] = x; r[1] = 0;
    }
    
    // Хелпер: проверить равенство
    function assertBigEq(uint256[2] memory a, uint256[2] memory b) internal {
        assertEq(a[0], b[0], "Low limbs match");
        assertEq(a[1], b[1], "High limbs match");
    }

    // 1. Тест сложения (простой)
    function testAddSimple() public {
        uint256[2] memory res = lib.add(mk(10), mk(20));
        assertEq(res[0], 30);
    }

    // 2. Тест вычитания с заемом (P - 5)
    function testSubUnderflow() public {
        uint256[2] memory a = mk(5);
        uint256[2] memory b = mk(10);
        uint256[2] memory res = lib.sub(a, b);
        
        // Ожидаем: P - 5
        // (P_LO - 5) с заемом из P_HI ? Нет, P_LO огромное.
        // P_LO - 5 = ...aaab - 5 = ...aaa6
        assertEq(res[0], P_LO - 5);
        assertEq(res[1], P_HI);
    }

    // 3. Тест Монтгомери: 1 * 1 = 1
    function testMontMulOne() public {
        uint256[2] memory one = mk(1);
        uint256[2] memory one_m = lib.toMontgomery(one);
        
        uint256[2] memory res_m = lib.montMul(one_m, one_m);
        uint256[2] memory res = lib.fromMontgomery(res_m);
        
        assertEq(res[0], 1);
        assertEq(res[1], 0);
    }
    
    // 4. Тест Монтгомери: 2 * 3 = 6
    function testMontMulSmall() public {
        uint256[2] memory a = lib.toMontgomery(mk(2));
        uint256[2] memory b = lib.toMontgomery(mk(3));
        
        uint256[2] memory res_m = lib.montMul(a, b);
        uint256[2] memory res = lib.fromMontgomery(res_m);
        
        assertEq(res[0], 6);
        assertEq(res[1], 0);
    }
    
    // 5. Тест: Сложение с переполнением модуля (P-1 + 5 = 4)
    function testAddModReduction() public {
        uint256[2] memory pm1; // P - 1
        pm1[0] = P_LO - 1;
        pm1[1] = P_HI;
        
        uint256[2] memory five = mk(5);
        uint256[2] memory res = lib.add(pm1, five);
        
        assertEq(res[0], 4);
        assertEq(res[1], 0);
    }
}
