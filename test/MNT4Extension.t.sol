// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MNT4Extension.sol";
import "../src/BigIntMNT.sol";

contract MNT4ExtensionHarness {
    using MNT4Extension for MNT4Extension.Fq2;
    using MNT4Extension for MNT4Extension.Fq4;

    function fq2Add(MNT4Extension.Fq2 memory a, MNT4Extension.Fq2 memory b) external pure returns (MNT4Extension.Fq2 memory) {
        return MNT4Extension.fq2Add(a, b);
    }
    function fq2Sub(MNT4Extension.Fq2 memory a, MNT4Extension.Fq2 memory b) external pure returns (MNT4Extension.Fq2 memory) {
        return MNT4Extension.fq2Sub(a, b);
    }
    function fq2Mul(MNT4Extension.Fq2 memory a, MNT4Extension.Fq2 memory b) external pure returns (MNT4Extension.Fq2 memory) {
        return MNT4Extension.fq2Mul(a, b);
    }

    function fq4Add(MNT4Extension.Fq4 memory a, MNT4Extension.Fq4 memory b) external pure returns (MNT4Extension.Fq4 memory) {
        return MNT4Extension.fq4Add(a, b);
    }
    function fq4Sub(MNT4Extension.Fq4 memory a, MNT4Extension.Fq4 memory b) external pure returns (MNT4Extension.Fq4 memory) {
        return MNT4Extension.fq4Sub(a, b);
    }
    function fq4Mul(MNT4Extension.Fq4 memory a, MNT4Extension.Fq4 memory b) external pure returns (MNT4Extension.Fq4 memory) {
        return MNT4Extension.fq4Mul(a, b);
    }
}

contract MNT4ExtensionTest is Test {
    MNT4ExtensionHarness lib;
    
    function setUp() public {
        lib = new MNT4ExtensionHarness();
    }

    function mk(uint256 x) internal pure returns (uint256[3] memory r) {
        r[0] = x; r[1] = 0; r[2] = 0;
    }

    function toMont(uint256 x) internal pure returns (uint256[3] memory) {
        return BigIntMNT.toMontgomery(mk(x));
    }

    function assertEq3(uint256[3] memory a, uint256[3] memory b) internal {
        assertEq(a[0], b[0], "Limb 0 mismatch");
        assertEq(a[1], b[1], "Limb 1 mismatch");
        assertEq(a[2], b[2], "Limb 2 mismatch");
    }

    function assertEqFq2(MNT4Extension.Fq2 memory a, MNT4Extension.Fq2 memory b) internal {
        assertEq3(a.c0, b.c0);
        assertEq3(a.c1, b.c1);
    }

    function assertEqFq4(MNT4Extension.Fq4 memory a, MNT4Extension.Fq4 memory b) internal {
        assertEqFq2(a.c0, b.c0);
        assertEqFq2(a.c1, b.c1);
    }

    // --- Basic Tests ---

    function testFq2Mul_Specific() public {
        MNT4Extension.Fq2 memory a;
        a.c0 = toMont(1); a.c1 = toMont(2);
        MNT4Extension.Fq2 memory b;
        b.c0 = toMont(3); b.c1 = toMont(4);

        MNT4Extension.Fq2 memory res = lib.fq2Mul(a, b);
        assertEq3(res.c0, toMont(107));
        assertEq3(res.c1, toMont(10));
    }

    function testFq4Mul_Identity() public {
        MNT4Extension.Fq4 memory a;
        a.c0.c0 = toMont(1); 
        MNT4Extension.Fq4 memory res = lib.fq4Mul(a, a);
        assertEq3(res.c0.c0, toMont(1));
        assertEq3(res.c0.c1, toMont(0));
    }

    // --- Fuzz Tests ---

    function boundModP(uint256[3] memory val) internal pure returns (uint256[3] memory) {
        val[2] = val[2] & 0x1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; 
        return val;
    }

    // (a * b) * c == a * (b * c)
    function testFuzz_Fq2Mul_Associativity(
        uint256[3] memory a0, uint256[3] memory a1,
        uint256[3] memory b0, uint256[3] memory b1,
        uint256[3] memory c0, uint256[3] memory c1
    ) public {
        a0 = boundModP(a0); a1 = boundModP(a1);
        b0 = boundModP(b0); b1 = boundModP(b1);
        c0 = boundModP(c0); c1 = boundModP(c1);

        MNT4Extension.Fq2 memory a; a.c0 = a0; a.c1 = a1;
        MNT4Extension.Fq2 memory b; b.c0 = b0; b.c1 = b1;
        MNT4Extension.Fq2 memory c; c.c0 = c0; c.c1 = c1;

        MNT4Extension.Fq2 memory ab = lib.fq2Mul(a, b);
        MNT4Extension.Fq2 memory res1 = lib.fq2Mul(ab, c);

        MNT4Extension.Fq2 memory bc = lib.fq2Mul(b, c);
        MNT4Extension.Fq2 memory res2 = lib.fq2Mul(a, bc);

        assertEqFq2(res1, res2);
    }

    // a * (b + c) == a*b + a*c
    function testFuzz_Fq2Mul_Distributivity(
        uint256[3] memory a0, uint256[3] memory a1,
        uint256[3] memory b0, uint256[3] memory b1,
        uint256[3] memory c0, uint256[3] memory c1
    ) public {
        a0 = boundModP(a0); a1 = boundModP(a1);
        b0 = boundModP(b0); b1 = boundModP(b1);
        c0 = boundModP(c0); c1 = boundModP(c1);

        MNT4Extension.Fq2 memory a; a.c0 = a0; a.c1 = a1;
        MNT4Extension.Fq2 memory b; b.c0 = b0; b.c1 = b1;
        MNT4Extension.Fq2 memory c; c.c0 = c0; c.c1 = c1;

        MNT4Extension.Fq2 memory b_plus_c = lib.fq2Add(b, c);
        MNT4Extension.Fq2 memory res1 = lib.fq2Mul(a, b_plus_c);

        MNT4Extension.Fq2 memory ab = lib.fq2Mul(a, b);
        MNT4Extension.Fq2 memory ac = lib.fq2Mul(a, c);
        MNT4Extension.Fq2 memory res2 = lib.fq2Add(ab, ac);

        assertEqFq2(res1, res2);
    }
}