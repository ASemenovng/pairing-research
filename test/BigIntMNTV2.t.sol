// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "forge-std/Test.sol";
import "../src/BigIntMNTV2.sol";

contract BigIntMNTHarness {
    function add(uint256[3] memory a, uint256[3] memory b) external pure returns (uint256[3] memory) {
        return BigIntMNTV2.add(a, b);
    }
    function sub(uint256[3] memory a, uint256[3] memory b) external pure returns (uint256[3] memory) {
        return BigIntMNTV2.sub(a, b);
    }
    function montMul(uint256[3] memory a, uint256[3] memory b) external pure returns (uint256[3] memory) {
        return BigIntMNTV2.montMul(a, b);
    }
    function toMontgomery(uint256[3] memory x) external pure returns (uint256[3] memory) {
        return BigIntMNTV2.toMontgomery(x);
    }
    function fromMontgomery(uint256[3] memory x) external pure returns (uint256[3] memory) {
        return BigIntMNTV2.fromMontgomery(x);
    }
    function montSqr(uint256[3] memory a) external pure returns (uint256[3] memory) {
        return BigIntMNTV2.montSqr(a);
    }
}

contract BigIntMNTTest is Test {
    BigIntMNTHarness lib;

    uint256 private constant P_0  = 0x685acce9767254a4638810719ac425f0e39d54522cdd119f5e9063de245e8001;
    uint256 private constant P_1  = 0x07fdb925e8a0ed8d99d124d9a15af79db117e776f218059db80f0da5cb537e38;
    uint256 private constant P_2  = 0x001c4c62d92c41110229022eee2cdadb7f997505b8fafed5eb7e8f96c97d873;

    function setUp() public {
        lib = new BigIntMNTHarness();
    }

    function mk(uint256 x) internal pure returns (uint256[3] memory r) {
        r[0] = x; r[1] = 0; r[2] = 0;
    }

    function pMinus1() internal pure returns (uint256[3] memory r) {
        r[0] = P_0 - 1;
        r[1] = P_1;
        r[2] = P_2;
    }

    function pMinus2() internal pure returns (uint256[3] memory r) {
        r[0] = P_0 - 2;
        r[1] = P_1;
        r[2] = P_2;
    }

    function assertEq3(uint256[3] memory a, uint256[3] memory b) internal {
        assertEq(a[0], b[0], "Limb 0 mismatch");
        assertEq(a[1], b[1], "Limb 1 mismatch");
        assertEq(a[2], b[2], "Limb 2 mismatch");
    }

    function testAddSimple() public {
        assertEq3(lib.add(mk(100), mk(200)), mk(300));
    }

    function testAddCarry() public {
        uint256[3] memory a; a[0] = type(uint256).max;
        uint256[3] memory res = lib.add(a, mk(1));
        assertEq(res[0], 0);
        assertEq(res[1], 1);
        assertEq(res[2], 0);
    }

    function testAddWrapModP() public {
        // (p-1) + 1 == 0 mod p
        assertEq3(lib.add(pMinus1(), mk(1)), mk(0));
    }

    function testAddLargeNoWrap() public {
        // (p-1) + (p-1) == p-2 mod p
        assertEq3(lib.add(pMinus1(), pMinus1()), pMinus2());
    }

    function testSubSimple() public {
        assertEq3(lib.sub(mk(10), mk(3)), mk(7));
    }

    function testSubUnderflow() public {
        // 5 - 6 == -1 == p-1
        uint256[3] memory res = lib.sub(mk(5), mk(6));
        assertEq3(res, pMinus1());
    }

    function testMontgomeryRoundtripSmall() public {
        uint256[3] memory x = mk(42);
        uint256[3] memory x_m = lib.toMontgomery(x);
        uint256[3] memory x_back = lib.fromMontgomery(x_m);
        assertEq3(x_back, x);
    }

    function testMontgomeryRoundtripLarge() public {
        uint256[3] memory x = pMinus1();
        uint256[3] memory x_m = lib.toMontgomery(x);
        uint256[3] memory x_back = lib.fromMontgomery(x_m);
        assertEq3(x_back, x);
    }

    function testMontMulSmall() public {
        uint256[3] memory a = mk(2);
        uint256[3] memory b = mk(3);
        uint256[3] memory am = lib.toMontgomery(a);
        uint256[3] memory bm = lib.toMontgomery(b);
        uint256[3] memory resM = lib.montMul(am, bm);
        uint256[3] memory res = lib.fromMontgomery(resM);
        assertEq3(res, mk(6));
    }

    function testMontMulNegOneSquare() public {
        // (-1)*(-1) == 1 mod p
        uint256[3] memory neg1 = pMinus1();
        uint256[3] memory one = mk(1);

        uint256[3] memory neg1m = lib.toMontgomery(neg1);
        uint256[3] memory resM = lib.montMul(neg1m, neg1m);
        uint256[3] memory res = lib.fromMontgomery(resM);

        assertEq3(res, one);
    }

    function testMontMulOne() public {
        // 1*1 == 1 (sanity)
        uint256[3] memory one = mk(1);
        uint256[3] memory one_m = lib.toMontgomery(one);
        uint256[3] memory res_m = lib.montMul(one_m, one_m);
        uint256[3] memory res = lib.fromMontgomery(res_m);
        assertEq3(res, one);
    }

    function testMontSqrMatchesMul() public {
        uint256[3] memory x = mk(1234567);
        uint256[3] memory xm = lib.toMontgomery(x);

        uint256[3] memory sq1 = lib.montSqr(xm);
        uint256[3] memory sq2 = lib.montMul(xm, xm);

        assertEq3(sq1, sq2);
    }
}