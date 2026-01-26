// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BigIntMNT.sol";

contract BigIntMNTHarness {
    function add(uint256[3] memory a, uint256[3] memory b) external pure returns (uint256[3] memory) {
        return BigIntMNT.add(a, b);
    }
    function sub(uint256[3] memory a, uint256[3] memory b) external pure returns (uint256[3] memory) {
        return BigIntMNT.sub(a, b);
    }
    function montMul(uint256[3] memory a, uint256[3] memory b) external pure returns (uint256[3] memory) {
        return BigIntMNT.montMul(a, b);
    } 
    function toMontgomery(uint256[3] memory x) external pure returns (uint256[3] memory) {
        return BigIntMNT.toMontgomery(x);
    }
    function fromMontgomery(uint256[3] memory x) external pure returns (uint256[3] memory) {
        return BigIntMNT.fromMontgomery(x);
    }
}

contract BigIntMNTTest is Test {
    BigIntMNTHarness lib;
    
    // Correct MNT4-753 Constants
    uint256 private constant P_0  = 0x685acce9767254a4638810719ac425f0e39d54522cdd119f5e9063de245e8001;
    uint256 private constant P_1  = 0x7fdb925e8a0ed8d99d124d9a15af79db117e776f218059db80f0da5cb537e38;
    uint256 private constant P_2  = 0x1c4c62d92c41110229022eee2cdadb7f997505b8fafed5eb7e8f96c97d873;

    function setUp() public {
        lib = new BigIntMNTHarness();
    }

    function mk(uint256 x) internal pure returns (uint256[3] memory r) {
        r[0] = x; r[1] = 0; r[2] = 0;
    }
    
    function assertEq3(uint256[3] memory a, uint256[3] memory b) internal {
        assertEq(a[0], b[0], "Limb 0 mismatch");
        assertEq(a[1], b[1], "Limb 1 mismatch");
        assertEq(a[2], b[2], "Limb 2 mismatch");
    }

    function testAddSimple() public {
        uint256[3] memory res = lib.add(mk(100), mk(200));
        assertEq3(res, mk(300));
    }
    
    function testAddCarry() public {
        uint256[3] memory a; a[0] = type(uint256).max;
        uint256[3] memory b = mk(1);
        uint256[3] memory res = lib.add(a, b);
        assertEq(res[0], 0);
        assertEq(res[1], 1);
    }

    function testSubSimple() public {
        assertEq3(lib.sub(mk(10), mk(3)), mk(7));
    }
    
    function testSubUnderflow() public {
        uint256[3] memory res = lib.sub(mk(5), mk(6));
        assertEq(res[0], P_0 - 1);
        assertEq(res[1], P_1);
        assertEq(res[2], P_2);
    }
    
    function testMontMul() public {
        uint256[3] memory a = mk(2);
        uint256[3] memory b = mk(3);
        uint256[3] memory am = lib.toMontgomery(a);
        uint256[3] memory bm = lib.toMontgomery(b);
        uint256[3] memory resM = lib.montMul(am, bm);
        uint256[3] memory res = lib.fromMontgomery(resM);
        assertEq3(res, mk(6));
    }

    function testMontMulOne() public {
        uint256[3] memory one = mk(1);
        uint256[3] memory one_m = lib.toMontgomery(one);
        uint256[3] memory res_m = lib.montMul(one_m, one_m);
        uint256[3] memory res = lib.fromMontgomery(res_m);
        assertEq3(res, mk(1));
    }

    function testMontgomeryRoundtrip() public {
        uint256[3] memory x = mk(42);
        uint256[3] memory x_m = lib.toMontgomery(x);
        uint256[3] memory x_back = lib.fromMontgomery(x_m);
        assertEq3(x_back, x);
    }
}