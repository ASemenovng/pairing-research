// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import "./BigIntMNTV2.sol";

/// @notice Fp2 = Fp[u]/(u^2-13), Fp4 = Fp2[v]/(v^2-u), all coefficients in Montgomery form.
library MNT4ExtensionV2 {
    struct Fq2 {
        uint256[3] c0;
        uint256[3] c1;
    }

    struct Fq4 {
        Fq2 c0;
        Fq2 c1;
    }

    // ========= small const 13*x over Fp (Montgomery) =========

    function fpMulBy13(
        uint256 x0, uint256 x1, uint256 x2
    ) internal pure returns (uint256 y0, uint256 y1, uint256 y2) {
        (uint256 x2_0, uint256 x2_1, uint256 x2_2) = BigIntMNTV2.add3(x0, x1, x2, x0, x1, x2);           // 2x
        (uint256 x4_0, uint256 x4_1, uint256 x4_2) = BigIntMNTV2.add3(x2_0, x2_1, x2_2, x2_0, x2_1, x2_2); // 4x
        (uint256 x8_0, uint256 x8_1, uint256 x8_2) = BigIntMNTV2.add3(x4_0, x4_1, x4_2, x4_0, x4_1, x4_2); // 8x
        (uint256 x12_0, uint256 x12_1, uint256 x12_2) = BigIntMNTV2.add3(x8_0, x8_1, x8_2, x4_0, x4_1, x4_2); // 12x
        (y0, y1, y2) = BigIntMNTV2.add3(x12_0, x12_1, x12_2, x0, x1, x2); // 13x
    }

    // ========= Fq2 basic =========

    function fq2Add(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory r) {
        (r.c0[0], r.c0[1], r.c0[2]) = BigIntMNTV2.add3(a.c0[0], a.c0[1], a.c0[2], b.c0[0], b.c0[1], b.c0[2]);
        (r.c1[0], r.c1[1], r.c1[2]) = BigIntMNTV2.add3(a.c1[0], a.c1[1], a.c1[2], b.c1[0], b.c1[1], b.c1[2]);
    }

    function fq2Sub(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory r) {
        (r.c0[0], r.c0[1], r.c0[2]) = BigIntMNTV2.sub3(a.c0[0], a.c0[1], a.c0[2], b.c0[0], b.c0[1], b.c0[2]);
        (r.c1[0], r.c1[1], r.c1[2]) = BigIntMNTV2.sub3(a.c1[0], a.c1[1], a.c1[2], b.c1[0], b.c1[1], b.c1[2]);
    }

    // ========= Fq2 mul/sqr (with To-variants) =========
    // NOTE: aliasing (out==a or out==b) is NOT guaranteed safe.

    function fq2MulTo(Fq2 memory out, Fq2 memory a, Fq2 memory b) internal pure {
        // v0 into out.c0
        (out.c0[0], out.c0[1], out.c0[2]) = BigIntMNTV2.montMul3(
            a.c0[0], a.c0[1], a.c0[2],
            b.c0[0], b.c0[1], b.c0[2]
        );

        // v1 into out.c1
        (out.c1[0], out.c1[1], out.c1[2]) = BigIntMNTV2.montMul3(
            a.c1[0], a.c1[1], a.c1[2],
            b.c1[0], b.c1[1], b.c1[2]
        );

        // s = v0+v1
        (uint256 s0, uint256 s1, uint256 s2) = BigIntMNTV2.add3(
            out.c0[0], out.c0[1], out.c0[2],
            out.c1[0], out.c1[1], out.c1[2]
        );

        // c0 = v0 + 13*v1
        (uint256 bv0, uint256 bv1, uint256 bv2) = fpMulBy13(out.c1[0], out.c1[1], out.c1[2]);
        (out.c0[0], out.c0[1], out.c0[2]) = BigIntMNTV2.add3(out.c0[0], out.c0[1], out.c0[2], bv0, bv1, bv2);

        // v2 = (a0+a1)*(b0+b1)
        (uint256 as0, uint256 as1, uint256 as2) = BigIntMNTV2.add3(
            a.c0[0], a.c0[1], a.c0[2],
            a.c1[0], a.c1[1], a.c1[2]
        );
        (uint256 bs0, uint256 bs1, uint256 bs2) = BigIntMNTV2.add3(
            b.c0[0], b.c0[1], b.c0[2],
            b.c1[0], b.c1[1], b.c1[2]
        );
        (uint256 v20, uint256 v21, uint256 v22) = BigIntMNTV2.montMul3(as0, as1, as2, bs0, bs1, bs2);

        // c1 = v2 - (v0+v1)
        (out.c1[0], out.c1[1], out.c1[2]) = BigIntMNTV2.sub3(v20, v21, v22, s0, s1, s2);
    }

    function fq2Mul(Fq2 memory a, Fq2 memory b) internal pure returns (Fq2 memory r) {
        fq2MulTo(r, a, b);
    }

    /// @notice Fq2 squaring:
    /// (a0 + a1*u)^2 = (a0^2 + 13*a1^2) + (2*a0*a1)u
    function fq2SqrTo(Fq2 memory out, Fq2 memory a) internal pure {
        // v0 = a0^2
        (uint256 v00, uint256 v01, uint256 v02) = BigIntMNTV2.montSqr3(a.c0[0], a.c0[1], a.c0[2]);
        // v1 = a1^2
        (uint256 v10, uint256 v11, uint256 v12) = BigIntMNTV2.montSqr3(a.c1[0], a.c1[1], a.c1[2]);

        // c0 = v0 + 13*v1
        (uint256 bv0, uint256 bv1, uint256 bv2) = fpMulBy13(v10, v11, v12);
        (out.c0[0], out.c0[1], out.c0[2]) = BigIntMNTV2.add3(v00, v01, v02, bv0, bv1, bv2);

        // t = a0*a1
        (uint256 t0, uint256 t1, uint256 t2) = BigIntMNTV2.montMul3(
            a.c0[0], a.c0[1], a.c0[2],
            a.c1[0], a.c1[1], a.c1[2]
        );

        // c1 = 2*t
        (out.c1[0], out.c1[1], out.c1[2]) = BigIntMNTV2.add3(t0, t1, t2, t0, t1, t2);
    }

    function fq2Sqr(Fq2 memory a) internal pure returns (Fq2 memory r) {
        fq2SqrTo(r, a);
    }

    /// @notice Multiply by u in Fq2: (x0 + x1*u)*u = (13*x1) + x0*u
    function fq2MulByUTo(Fq2 memory out, Fq2 memory x) internal pure {
        (out.c0[0], out.c0[1], out.c0[2]) = fpMulBy13(x.c1[0], x.c1[1], x.c1[2]);
        out.c1 = x.c0;
    }

    function fq2MulByU(Fq2 memory x) internal pure returns (Fq2 memory r) {
        fq2MulByUTo(r, x);
    }

    /// @notice Multiply Fq2 by scalar in Fp (Montgomery): (a0+a1*u)*s
    function fq2MulByFpTo(Fq2 memory out, Fq2 memory a, uint256[3] memory s) internal pure {
        (out.c0[0], out.c0[1], out.c0[2]) = BigIntMNTV2.montMul3(a.c0[0], a.c0[1], a.c0[2], s[0], s[1], s[2]);
        (out.c1[0], out.c1[1], out.c1[2]) = BigIntMNTV2.montMul3(a.c1[0], a.c1[1], a.c1[2], s[0], s[1], s[2]);
    }

    function fq2MulByFp(Fq2 memory a, uint256[3] memory s) internal pure returns (Fq2 memory r) {
        fq2MulByFpTo(r, a, s);
    }

    // ========= Fq4 mul/sqr + sparse helpers =========

    function fq4Add(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory r) {
        r.c0 = fq2Add(a.c0, b.c0);
        r.c1 = fq2Add(a.c1, b.c1);
    }

    function fq4Sub(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory r) {
        r.c0 = fq2Sub(a.c0, b.c0);
        r.c1 = fq2Sub(a.c1, b.c1);
    }

    function fq4MulTo(Fq4 memory out, Fq4 memory a, Fq4 memory b) internal pure {
        // Use out.c0 as v0, out.c1 as v1 (scratch)
        fq2MulTo(out.c0, a.c0, b.c0); // v0
        fq2MulTo(out.c1, a.c1, b.c1); // v1

        // s = v0+v1 (store in locals)
        (uint256 s00, uint256 s01, uint256 s02) = BigIntMNTV2.add3(
            out.c0.c0[0], out.c0.c0[1], out.c0.c0[2],
            out.c1.c0[0], out.c1.c0[1], out.c1.c0[2]
        );
        (uint256 s10, uint256 s11, uint256 s12) = BigIntMNTV2.add3(
            out.c0.c1[0], out.c0.c1[1], out.c0.c1[2],
            out.c1.c1[0], out.c1.c1[1], out.c1.c1[2]
        );

        // c0 = v0 + u*v1
        // u*v1 = (13*v1.c1) + (v1.c0)*u
        (uint256 uv0, uint256 uv1, uint256 uv2) = fpMulBy13(out.c1.c1[0], out.c1.c1[1], out.c1.c1[2]); // 13*v1.c1
        (out.c0.c0[0], out.c0.c0[1], out.c0.c0[2]) = BigIntMNTV2.add3(
            out.c0.c0[0], out.c0.c0[1], out.c0.c0[2],
            uv0, uv1, uv2
        );
        // out.c0.c1 += v1.c0
        (out.c0.c1[0], out.c0.c1[1], out.c0.c1[2]) = BigIntMNTV2.add3(
            out.c0.c1[0], out.c0.c1[1], out.c0.c1[2],
            out.c1.c0[0], out.c1.c0[1], out.c1.c0[2]
        );

        // v2 = (a0+a1)*(b0+b1) -> compute aSum,bSum without extra fq2Add allocations
        Fq2 memory aSum;
        (aSum.c0[0], aSum.c0[1], aSum.c0[2]) = BigIntMNTV2.add3(
            a.c0.c0[0], a.c0.c0[1], a.c0.c0[2],
            a.c1.c0[0], a.c1.c0[1], a.c1.c0[2]
        );
        (aSum.c1[0], aSum.c1[1], aSum.c1[2]) = BigIntMNTV2.add3(
            a.c0.c1[0], a.c0.c1[1], a.c0.c1[2],
            a.c1.c1[0], a.c1.c1[1], a.c1.c1[2]
        );

        Fq2 memory bSum;
        (bSum.c0[0], bSum.c0[1], bSum.c0[2]) = BigIntMNTV2.add3(
            b.c0.c0[0], b.c0.c0[1], b.c0.c0[2],
            b.c1.c0[0], b.c1.c0[1], b.c1.c0[2]
        );
        (bSum.c1[0], bSum.c1[1], bSum.c1[2]) = BigIntMNTV2.add3(
            b.c0.c1[0], b.c0.c1[1], b.c0.c1[2],
            b.c1.c1[0], b.c1.c1[1], b.c1.c1[2]
        );

        // overwrite out.c1 with v2
        fq2MulTo(out.c1, aSum, bSum);

        // c1 = v2 - (v0+v1) = out.c1 - s
        (out.c1.c0[0], out.c1.c0[1], out.c1.c0[2]) = BigIntMNTV2.sub3(
            out.c1.c0[0], out.c1.c0[1], out.c1.c0[2],
            s00, s01, s02
        );
        (out.c1.c1[0], out.c1.c1[1], out.c1.c1[2]) = BigIntMNTV2.sub3(
            out.c1.c1[0], out.c1.c1[1], out.c1.c1[2],
            s10, s11, s12
        );
    }

    function fq4Mul(Fq4 memory a, Fq4 memory b) internal pure returns (Fq4 memory r) {
        fq4MulTo(r, a, b);
    }

    /// @notice Fq4 squaring: (c0 + c1*v)^2 = (c0^2 + u*c1^2) + (2*c0*c1)*v, with v^2=u
    function fq4SqrTo(Fq4 memory out, Fq4 memory a) internal pure {
        // out.c0 = c0^2
        fq2SqrTo(out.c0, a.c0);

        // out.c1 = c1^2 (temporary)
        fq2SqrTo(out.c1, a.c1);

        // out.c0 += u*(c1^2)
        // u*(x0 + x1*u) = (13*x1) + x0*u
        (uint256 ux0, uint256 ux1, uint256 ux2) = fpMulBy13(out.c1.c1[0], out.c1.c1[1], out.c1.c1[2]);
        (out.c0.c0[0], out.c0.c0[1], out.c0.c0[2]) = BigIntMNTV2.add3(
            out.c0.c0[0], out.c0.c0[1], out.c0.c0[2],
            ux0, ux1, ux2
        );
        (out.c0.c1[0], out.c0.c1[1], out.c0.c1[2]) = BigIntMNTV2.add3(
            out.c0.c1[0], out.c0.c1[1], out.c0.c1[2],
            out.c1.c0[0], out.c1.c0[1], out.c1.c0[2]
        );

        // out.c1 = 2*c0*c1
        fq2MulTo(out.c1, a.c0, a.c1);
        // double out.c1
        (out.c1.c0[0], out.c1.c0[1], out.c1.c0[2]) = BigIntMNTV2.add3(
            out.c1.c0[0], out.c1.c0[1], out.c1.c0[2],
            out.c1.c0[0], out.c1.c0[1], out.c1.c0[2]
        );
        (out.c1.c1[0], out.c1.c1[1], out.c1.c1[2]) = BigIntMNTV2.add3(
            out.c1.c1[0], out.c1.c1[1], out.c1.c1[2],
            out.c1.c1[0], out.c1.c1[1], out.c1.c1[2]
        );
    }

    function fq4Sqr(Fq4 memory a) internal pure returns (Fq4 memory r) {
        fq4SqrTo(r, a);
    }

    /// @notice Multiply Fq4 by scalar in Fq2: (a0+a1*v)*s = (a0*s) + (a1*s)*v
    function fq4MulByFq2To(Fq4 memory out, Fq4 memory a, Fq2 memory s) internal pure {
        fq2MulTo(out.c0, a.c0, s);
        fq2MulTo(out.c1, a.c1, s);
    }

    function fq4MulByFq2(Fq4 memory a, Fq2 memory s) internal pure returns (Fq4 memory r) {
        fq4MulByFq2To(r, a, s);
    }

    /// @notice Multiply by v in Fq4: (c0 + c1*v)*v = (u*c1) + c0*v
    function fq4MulByV(Fq4 memory a) internal pure returns (Fq4 memory r) {
        // r.c0 = u*c1
        fq2MulByUTo(r.c0, a.c1);
        // r.c1 = c0
        r.c1 = a.c0;
    }
}