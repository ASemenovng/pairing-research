// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "forge-std/Test.sol";
import "../src/MNT4ExtensionV2.sol";
import "../src/BigIntMNTV2.sol";

contract MNT4ExtensionV2Harness {
    function fq2Add(MNT4ExtensionV2.Fq2 memory a, MNT4ExtensionV2.Fq2 memory b)
        external
        pure
        returns (MNT4ExtensionV2.Fq2 memory)
    {
        return MNT4ExtensionV2.fq2Add(a, b);
    }

    function fq2Sub(MNT4ExtensionV2.Fq2 memory a, MNT4ExtensionV2.Fq2 memory b)
        external
        pure
        returns (MNT4ExtensionV2.Fq2 memory)
    {
        return MNT4ExtensionV2.fq2Sub(a, b);
    }

    function fq2Mul(MNT4ExtensionV2.Fq2 memory a, MNT4ExtensionV2.Fq2 memory b)
        external
        pure
        returns (MNT4ExtensionV2.Fq2 memory)
    {
        return MNT4ExtensionV2.fq2Mul(a, b);
    }

    function fq4Mul(MNT4ExtensionV2.Fq4 memory a, MNT4ExtensionV2.Fq4 memory b)
        external
        pure
        returns (MNT4ExtensionV2.Fq4 memory)
    {
        return MNT4ExtensionV2.fq4Mul(a, b);
    }

    function fq2Sqr(MNT4ExtensionV2.Fq2 memory a) external pure returns (MNT4ExtensionV2.Fq2 memory) {
        return MNT4ExtensionV2.fq2Sqr(a);
    }

    function fq4Sqr(MNT4ExtensionV2.Fq4 memory a) external pure returns (MNT4ExtensionV2.Fq4 memory) {
        return MNT4ExtensionV2.fq4Sqr(a);
    }

    function fq4MulByV(MNT4ExtensionV2.Fq4 memory a) external pure returns (MNT4ExtensionV2.Fq4 memory) {
        return MNT4ExtensionV2.fq4MulByV(a);
    }

    function benchFq4Sqr(uint256 n, MNT4ExtensionV2.Fq4 calldata x)
        external
        pure
        returns (MNT4ExtensionV2.Fq4 memory r)
    {
        // ping-pong buffers to avoid allocating every iteration
        MNT4ExtensionV2.Fq4 memory a = x;
        MNT4ExtensionV2.Fq4 memory b;

        unchecked {
            for (uint256 i = 0; i < n; ++i) {
                if (i & 1 == 0) {
                    MNT4ExtensionV2.fq4SqrTo(b, a);
                } else {
                    MNT4ExtensionV2.fq4SqrTo(a, b);
                }
            }
        }

        // if n is even -> a holds last result, else -> b
        r = (n & 1 == 0) ? a : b;
    }

    function benchFq4Mul(uint256 n, MNT4ExtensionV2.Fq4 calldata x, MNT4ExtensionV2.Fq4 calldata y)
        external
        pure
        returns (MNT4ExtensionV2.Fq4 memory r)
    {
        MNT4ExtensionV2.Fq4 memory a = x;
        MNT4ExtensionV2.Fq4 memory b;
        MNT4ExtensionV2.Fq4 memory ym = y; // copy once from calldata

        unchecked {
            for (uint256 i = 0; i < n; ++i) {
                if (i & 1 == 0) {
                    MNT4ExtensionV2.fq4MulTo(b, a, ym);
                } else {
                    MNT4ExtensionV2.fq4MulTo(a, b, ym);
                }
            }
        }

        r = (n & 1 == 0) ? a : b;
    }
}

contract MNT4ExtensionV2Test is Test {
    MNT4ExtensionV2Harness lib;

    function setUp() public {
        lib = new MNT4ExtensionV2Harness();
    }

    function mk(uint256 x) internal pure returns (uint256[3] memory r) {
        r[0] = x; r[1] = 0; r[2] = 0;
    }

    function toMontU(uint256 x) internal pure returns (uint256[3] memory) {
        return BigIntMNTV2.toMontgomery(mk(x));
    }

    function assertEq3(uint256[3] memory a, uint256[3] memory b) internal {
        assertEq(a[0], b[0], "Limb0");
        assertEq(a[1], b[1], "Limb1");
        assertEq(a[2], b[2], "Limb2");
    }

    function assertEqFq2(MNT4ExtensionV2.Fq2 memory a, MNT4ExtensionV2.Fq2 memory b) internal {
        assertEq3(a.c0, b.c0);
        assertEq3(a.c1, b.c1);
    }

    function assertEqFq4(MNT4ExtensionV2.Fq4 memory a, MNT4ExtensionV2.Fq4 memory b) internal {
        assertEqFq2(a.c0, b.c0);
        assertEqFq2(a.c1, b.c1);
    }

    // ----------------------------
    // Concrete vector (Fp2)
    // (1 + 2u)*(3 + 4u) = (107 + 10u) in Fp2, since u^2=13
    // ----------------------------
    function testFq2Mul_Specific() public {
        MNT4ExtensionV2.Fq2 memory a;
        a.c0 = toMontU(1);
        a.c1 = toMontU(2);

        MNT4ExtensionV2.Fq2 memory b;
        b.c0 = toMontU(3);
        b.c1 = toMontU(4);

        MNT4ExtensionV2.Fq2 memory r = lib.fq2Mul(a, b);

        assertEq3(r.c0, toMontU(107));
        assertEq3(r.c1, toMontU(10));
    }

    // ----------------------------
    // Concrete vector (Fp4)
    // Fp4 = Fp2[v]/(v^2 - u)
    // Let:
    //   a0 = (1 + 2u), a1 = (3 + 4u)
    //   b0 = (5 + 6u), b1 = (7 + 8u)
    // Then:
    //   c0 = a0*b0 + (a1*b1)*u = (837 + 453u)
    //   c1 = a0*b1 + a1*b0      = (542 + 60u)
    // ----------------------------
    function testFq4Mul_Specific() public {
        MNT4ExtensionV2.Fq4 memory a;
        a.c0.c0 = toMontU(1);
        a.c0.c1 = toMontU(2);
        a.c1.c0 = toMontU(3);
        a.c1.c1 = toMontU(4);

        MNT4ExtensionV2.Fq4 memory b;
        b.c0.c0 = toMontU(5);
        b.c0.c1 = toMontU(6);
        b.c1.c0 = toMontU(7);
        b.c1.c1 = toMontU(8);

        MNT4ExtensionV2.Fq4 memory r = lib.fq4Mul(a, b);

        assertEq3(r.c0.c0, toMontU(837));
        assertEq3(r.c0.c1, toMontU(453));
        assertEq3(r.c1.c0, toMontU(542));
        assertEq3(r.c1.c1, toMontU(60));
    }

    function testFq4Mul_Identity() public {
        MNT4ExtensionV2.Fq4 memory one;
        one.c0.c0 = toMontU(1); // 1 in Fp2
        // rest are 0

        MNT4ExtensionV2.Fq4 memory r = lib.fq4Mul(one, one);

        assertEq3(r.c0.c0, toMontU(1));
        assertEq3(r.c0.c1, toMontU(0));
        assertEq3(r.c1.c0, toMontU(0));
        assertEq3(r.c1.c1, toMontU(0));
    }

    // ----------------------------
    // Fuzz (small scalars => always reduced, always Montgomery)
    // ----------------------------

    function fq2FromU64(uint64 x0, uint64 x1) internal pure returns (MNT4ExtensionV2.Fq2 memory a) {
        a.c0 = BigIntMNTV2.toMontgomery(mk(uint256(x0)));
        a.c1 = BigIntMNTV2.toMontgomery(mk(uint256(x1)));
    }

    function testFuzz_Fq2Mul_Associativity(uint64 a0, uint64 a1, uint64 b0, uint64 b1, uint64 c0, uint64 c1) public {
        MNT4ExtensionV2.Fq2 memory a = fq2FromU64(a0, a1);
        MNT4ExtensionV2.Fq2 memory b = fq2FromU64(b0, b1);
        MNT4ExtensionV2.Fq2 memory c = fq2FromU64(c0, c1);

        MNT4ExtensionV2.Fq2 memory ab = lib.fq2Mul(a, b);
        MNT4ExtensionV2.Fq2 memory r1 = lib.fq2Mul(ab, c);

        MNT4ExtensionV2.Fq2 memory bc = lib.fq2Mul(b, c);
        MNT4ExtensionV2.Fq2 memory r2 = lib.fq2Mul(a, bc);

        assertEqFq2(r1, r2);
    }

    function testFuzz_Fq2Mul_Distributivity(uint64 a0, uint64 a1, uint64 b0, uint64 b1, uint64 c0, uint64 c1) public {
        MNT4ExtensionV2.Fq2 memory a = fq2FromU64(a0, a1);
        MNT4ExtensionV2.Fq2 memory b = fq2FromU64(b0, b1);
        MNT4ExtensionV2.Fq2 memory c = fq2FromU64(c0, c1);

        MNT4ExtensionV2.Fq2 memory bpc = lib.fq2Add(b, c);
        MNT4ExtensionV2.Fq2 memory r1 = lib.fq2Mul(a, bpc);

        MNT4ExtensionV2.Fq2 memory ab = lib.fq2Mul(a, b);
        MNT4ExtensionV2.Fq2 memory ac = lib.fq2Mul(a, c);
        MNT4ExtensionV2.Fq2 memory r2 = lib.fq2Add(ab, ac);

        assertEqFq2(r1, r2);
    }

    function testFuzz_Fq4Mul_Associativity(
        uint64 a00, uint64 a01, uint64 a10, uint64 a11,
        uint64 b00, uint64 b01, uint64 b10, uint64 b11,
        uint64 c00, uint64 c01, uint64 c10, uint64 c11
    ) public {
        MNT4ExtensionV2.Fq4 memory a;
        a.c0 = fq2FromU64(a00, a01);
        a.c1 = fq2FromU64(a10, a11);

        MNT4ExtensionV2.Fq4 memory b;
        b.c0 = fq2FromU64(b00, b01);
        b.c1 = fq2FromU64(b10, b11);

        MNT4ExtensionV2.Fq4 memory c;
        c.c0 = fq2FromU64(c00, c01);
        c.c1 = fq2FromU64(c10, c11);

        MNT4ExtensionV2.Fq4 memory ab = lib.fq4Mul(a, b);
        MNT4ExtensionV2.Fq4 memory r1 = lib.fq4Mul(ab, c);

        MNT4ExtensionV2.Fq4 memory bc = lib.fq4Mul(b, c);
        MNT4ExtensionV2.Fq4 memory r2 = lib.fq4Mul(a, bc);

        assertEqFq4(r1, r2);
    }

    function testFq2Sqr_MatchesMul() public {
        MNT4ExtensionV2.Fq2 memory a;
        a.c0 = toMontU(11);
        a.c1 = toMontU(22);

        MNT4ExtensionV2.Fq2 memory s1 = lib.fq2Sqr(a);
        MNT4ExtensionV2.Fq2 memory s2 = lib.fq2Mul(a, a);

        assertEqFq2(s1, s2);
    }

    function testFq4Sqr_MatchesMul() public {
        MNT4ExtensionV2.Fq4 memory a;
        a.c0.c0 = toMontU(1);
        a.c0.c1 = toMontU(2);
        a.c1.c0 = toMontU(3);
        a.c1.c1 = toMontU(4);

        MNT4ExtensionV2.Fq4 memory s1 = lib.fq4Sqr(a);
        MNT4ExtensionV2.Fq4 memory s2 = lib.fq4Mul(a, a);

        assertEqFq4(s1, s2);
    }

    function testFq4MulByV_MatchesGeneralMul() public {
        // v = (0) + (1)*v
        MNT4ExtensionV2.Fq4 memory v;
        v.c1.c0 = toMontU(1); // Fq2 one = (1,0), so v = (0, 1)

        MNT4ExtensionV2.Fq4 memory a;
        a.c0.c0 = toMontU(5);
        a.c0.c1 = toMontU(6);
        a.c1.c0 = toMontU(7);
        a.c1.c1 = toMontU(8);

        MNT4ExtensionV2.Fq4 memory r1 = lib.fq4MulByV(a);
        MNT4ExtensionV2.Fq4 memory r2 = lib.fq4Mul(a, v);

        assertEqFq4(r1, r2);
    }

    function testBenchFq4Sqr64() public {
        MNT4ExtensionV2.Fq4 memory a;
        a.c0.c0 = toMontU(1);
        a.c0.c1 = toMontU(2);
        a.c1.c0 = toMontU(3);
        a.c1.c1 = toMontU(4);

        lib.benchFq4Sqr(64, a);
    }

    function testBenchFq4Mul32() public {
        MNT4ExtensionV2.Fq4 memory a;
        a.c0.c0 = toMontU(5);
        a.c0.c1 = toMontU(6);
        a.c1.c0 = toMontU(7);
        a.c1.c1 = toMontU(8);

        MNT4ExtensionV2.Fq4 memory b;
        b.c0.c0 = toMontU(9);
        b.c0.c1 = toMontU(10);
        b.c1.c0 = toMontU(11);
        b.c1.c1 = toMontU(12);

        lib.benchFq4Mul(32, a, b);
    }
}