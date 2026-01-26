// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @notice Base-field arithmetic mod p for MNT4-753, 3x256-bit limbs (little-endian).
///         Representation invariant:
///         - Inputs to add/sub/montMul/montSqr are assumed reduced: 0 <= x < p.
///         - Outputs are reduced.
/// @dev Montgomery radix B = 2^256, n=3 => R=2^768.
///      MAGIC = -p^{-1} mod 2^256.
library BigIntMNTV2 {
    uint256 private constant P_0  = 0x685acce9767254a4638810719ac425f0e39d54522cdd119f5e9063de245e8001;
    uint256 private constant P_1  = 0x7fdb925e8a0ed8d99d124d9a15af79db117e776f218059db80f0da5cb537e38;
    uint256 private constant P_2  = 0x1c4c62d92c41110229022eee2cdadb7f997505b8fafed5eb7e8f96c97d873;

    uint256 private constant R2_0 = 0xa896a656a0714c7da24bea56242b3507c7d9ff8e7df03c0a84717088cfd190c8;
    uint256 private constant R2_1 = 0xe03c79cac4f7ef07a8c86d4604a3b5972f47839ef88d7ce880a46659ff6f3ddf;
    uint256 private constant R2_2 = 0x2a33e89cb485b081f15bcbfdacaf8e4605754c3817232505daf1f4a81245;

    uint256 private constant MAGIC = 0x4adb7a6352a3a656d9e1947eee113b7a7fd403903e304c4cf2044cfbe45e7fff;

    function add3(
        uint256 a0, uint256 a1, uint256 a2,
        uint256 b0, uint256 b1, uint256 b2
    ) internal pure returns (uint256 r0, uint256 r1, uint256 r2) {
        assembly ("memory-safe") {
            function adc(x, y, c) -> r, cOut {
                let s := add(x, y)
                let c1 := lt(s, x)
                r := add(s, c)
                let c2 := lt(r, s)
                cOut := or(c1, c2)
            }
            function sbb(x, y, b) -> rr, bOut {
                let yy := add(y, b)
                rr := sub(x, yy)
                bOut := or(lt(x, yy), lt(yy, y))
            }

            let c := 0
            r0, c := adc(a0, b0, 0)
            r1, c := adc(a1, b1, c)
            r2, c := adc(a2, b2, c)

            let ge := 0
            if gt(r2, P_2) { ge := 1 }
            if eq(r2, P_2) {
                if gt(r1, P_1) { ge := 1 }
                if eq(r1, P_1) {
                    if iszero(lt(r0, P_0)) { ge := 1 }
                }
            }

            if ge {
                let bor := 0
                r0, bor := sbb(r0, P_0, 0)
                r1, bor := sbb(r1, P_1, bor)
                r2, bor := sbb(r2, P_2, bor)
            }
        }
    }

    function sub3(
        uint256 a0, uint256 a1, uint256 a2,
        uint256 b0, uint256 b1, uint256 b2
    ) internal pure returns (uint256 r0, uint256 r1, uint256 r2) {
        assembly ("memory-safe") {
            function sbb(x, y, b) -> rr, bOut {
                let yy := add(y, b)
                rr := sub(x, yy)
                bOut := or(lt(x, yy), lt(yy, y))
            }
            function adc(x, y, c) -> rr, cOut {
                let s := add(x, y)
                let c1 := lt(s, x)
                rr := add(s, c)
                let c2 := lt(rr, s)
                cOut := or(c1, c2)
            }

            let bor := 0
            r0, bor := sbb(a0, b0, 0)
            r1, bor := sbb(a1, b1, bor)
            r2, bor := sbb(a2, b2, bor)

            if bor {
                let c := 0
                r0, c := adc(r0, P_0, 0)
                r1, c := adc(r1, P_1, c)
                r2, c := adc(r2, P_2, c)
            }
        }
    }

    function montMul3(
        uint256 a0, uint256 a1, uint256 a2,
        uint256 b0, uint256 b1, uint256 b2
    ) internal pure returns (uint256 r0, uint256 r1, uint256 r2) {
        assembly ("memory-safe") {
            function mul512(u, v) -> lo, hi {
                lo := mul(u, v)
                let mm := mulmod(u, v, not(0))
                hi := sub(sub(mm, lo), lt(mm, lo))
            }

            let p0 := P_0
            let p1 := P_1
            let p2 := P_2
            let magic := MAGIC

            let t0 := 0
            let t1 := 0
            let t2 := 0
            let t3 := 0

            {
                let u := a0
                {
                    let lo, hi := mul512(u, b0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                }
                {
                    let lo, hi := mul512(u, b1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                {
                    let lo, hi := mul512(u, b2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }

                let m := mul(t0, magic)

                {
                    let lo, hi := mul512(m, p0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                {
                    let lo, hi := mul512(m, p1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                {
                    let lo, hi := mul512(m, p2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }

            t0 := t1
            t1 := t2
            t2 := t3
            t3 := 0

            {
                let u := a1
                {
                    let lo, hi := mul512(u, b0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                {
                    let lo, hi := mul512(u, b1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                {
                    let lo, hi := mul512(u, b2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }

                let m := mul(t0, magic)

                {
                    let lo, hi := mul512(m, p0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                {
                    let lo, hi := mul512(m, p1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                {
                    let lo, hi := mul512(m, p2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }

            t0 := t1
            t1 := t2
            t2 := t3
            t3 := 0

            {
                let u := a2
                {
                    let lo, hi := mul512(u, b0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                {
                    let lo, hi := mul512(u, b1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                {
                    let lo, hi := mul512(u, b2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }

                let m := mul(t0, magic)

                {
                    let lo, hi := mul512(m, p0)
                    t0 := add(t0, lo)
                    let c := lt(t0, lo)
                    t1 := add(t1, hi)
                    let c2 := lt(t1, hi)
                    t1 := add(t1, c)
                    if lt(t1, c) { c2 := add(c2, 1) }
                    t2 := add(t2, c2)
                    if lt(t2, c2) { t3 := add(t3, 1) }
                }
                {
                    let lo, hi := mul512(m, p1)
                    t1 := add(t1, lo)
                    let c := lt(t1, lo)
                    t2 := add(t2, hi)
                    let c2 := lt(t2, hi)
                    t2 := add(t2, c)
                    if lt(t2, c) { c2 := add(c2, 1) }
                    t3 := add(t3, c2)
                }
                {
                    let lo, hi := mul512(m, p2)
                    t2 := add(t2, lo)
                    let c := lt(t2, lo)
                    t3 := add(t3, hi)
                    t3 := add(t3, c)
                }
            }

            t0 := t1
            t1 := t2
            t2 := t3

            let ge := 0
            if gt(t2, p2) { ge := 1 }
            if eq(t2, p2) {
                if gt(t1, p1) { ge := 1 }
                if eq(t1, p1) {
                    if iszero(lt(t0, p0)) { ge := 1 }
                }
            }

            if ge {
                function sbb(x, y, b) -> rr, bOut {
                    let yy := add(y, b)
                    rr := sub(x, yy)
                    bOut := or(lt(x, yy), lt(yy, y))
                }
                let bor := 0
                t0, bor := sbb(t0, p0, 0)
                t1, bor := sbb(t1, p1, bor)
                t2, bor := sbb(t2, p2, bor)
            }

            r0 := t0
            r1 := t1
            r2 := t2
        }
    }

    /// @notice Montgomery squaring specialized for n=3 limbs.
    /// @dev Computes a^2 * R^{-1} mod p. Assumes a reduced (<p).
    function montSqr3(
        uint256 a0, uint256 a1, uint256 a2
    ) internal pure returns (uint256 r0, uint256 r1, uint256 r2) {
        assembly ("memory-safe") {
            function mul512(u, v) -> lo, hi {
                lo := mul(u, v)
                let mm := mulmod(u, v, not(0))
                hi := sub(sub(mm, lo), lt(mm, lo))
            }
            function adc(x, y, c) -> rr, cOut {
                let s := add(x, y)
                let c1 := lt(s, x)
                rr := add(s, c)
                let c2 := lt(rr, s)
                cOut := or(c1, c2)
            }
            function sbb(x, y, b) -> rr, bOut {
                let yy := add(y, b)
                rr := sub(x, yy)
                bOut := or(lt(x, yy), lt(yy, y))
            }

            // 7 limbs to safely catch top carry during accumulation/REDC
            let t0 := 0
            let t1 := 0
            let t2 := 0
            let t3 := 0
            let t4 := 0
            let t5 := 0
            let t6 := 0

            // p00 at offset 0
            {
                let lo, hi := mul512(a0, a0)
                t0 := lo
                t1 := hi
            }

            // helper macro: add (lo,hi,co) at offset k with full carry propagation to t6
            // (we inline per-offset below to keep Yul simple)

            // 2*p01 at offset 1
            {
                let lo, hi := mul512(a0, a1)

                // double 512-bit (lo,hi) -> (lo2, hi2) plus carryOut beyond 512
                let c0 := shr(255, lo)
                let lo2 := shl(1, lo)

                let hi2base := shl(1, hi)
                let hi2 := add(hi2base, c0)

                // carryOut = (hi >> 255) OR overflow from (hi2base + c0)
                let co := or(shr(255, hi), lt(hi2, hi2base))

                let c := 0
                t1, c := adc(t1, lo2, 0)
                t2, c := adc(t2, hi2, c)
                t3, c := adc(t3, co, c)
                t4, c := adc(t4, 0, c)
                t5, c := adc(t5, 0, c)
                t6, c := adc(t6, 0, c)
            }

            // 2*p02 at offset 2
            {
                let lo, hi := mul512(a0, a2)

                let c0 := shr(255, lo)
                let lo2 := shl(1, lo)

                let hi2base := shl(1, hi)
                let hi2 := add(hi2base, c0)
                let co := or(shr(255, hi), lt(hi2, hi2base))

                let c := 0
                t2, c := adc(t2, lo2, 0)
                t3, c := adc(t3, hi2, c)
                t4, c := adc(t4, co, c)
                t5, c := adc(t5, 0, c)
                t6, c := adc(t6, 0, c)
            }

            // p11 at offset 2
            {
                let lo, hi := mul512(a1, a1)
                let c := 0
                t2, c := adc(t2, lo, 0)
                t3, c := adc(t3, hi, c)
                t4, c := adc(t4, 0, c)
                t5, c := adc(t5, 0, c)
                t6, c := adc(t6, 0, c)
            }

            // 2*p12 at offset 3
            {
                let lo, hi := mul512(a1, a2)

                let c0 := shr(255, lo)
                let lo2 := shl(1, lo)

                let hi2base := shl(1, hi)
                let hi2 := add(hi2base, c0)
                let co := or(shr(255, hi), lt(hi2, hi2base))

                let c := 0
                t3, c := adc(t3, lo2, 0)
                t4, c := adc(t4, hi2, c)
                t5, c := adc(t5, co, c)
                t6, c := adc(t6, 0, c)
            }

            // p22 at offset 4
            {
                let lo, hi := mul512(a2, a2)
                let c := 0
                t4, c := adc(t4, lo, 0)
                t5, c := adc(t5, hi, c)
                t6, c := adc(t6, 0, c)
            }

            // Montgomery REDC (n=3) on t0..t6
            let p0 := P_0
            let p1 := P_1
            let p2 := P_2
            let magic := MAGIC

            for { let i := 0 } lt(i, 3) { i := add(i, 1) } {
                let m := mul(t0, magic)

                // add m*p0 at offset 0
                {
                    let lo, hi := mul512(m, p0)
                    let c := 0
                    t0, c := adc(t0, lo, 0)
                    t1, c := adc(t1, hi, c)
                    t2, c := adc(t2, 0, c)
                    t3, c := adc(t3, 0, c)
                    t4, c := adc(t4, 0, c)
                    t5, c := adc(t5, 0, c)
                    t6, c := adc(t6, 0, c)
                }

                // add m*p1 at offset 1
                {
                    let lo, hi := mul512(m, p1)
                    let c := 0
                    t1, c := adc(t1, lo, 0)
                    t2, c := adc(t2, hi, c)
                    t3, c := adc(t3, 0, c)
                    t4, c := adc(t4, 0, c)
                    t5, c := adc(t5, 0, c)
                    t6, c := adc(t6, 0, c)
                }

                // add m*p2 at offset 2
                {
                    let lo, hi := mul512(m, p2)
                    let c := 0
                    t2, c := adc(t2, lo, 0)
                    t3, c := adc(t3, hi, c)
                    t4, c := adc(t4, 0, c)
                    t5, c := adc(t5, 0, c)
                    t6, c := adc(t6, 0, c)
                }

                // divide by B (shift limbs down)
                t0 := t1
                t1 := t2
                t2 := t3
                t3 := t4
                t4 := t5
                t5 := t6
                t6 := 0
            }

            // Final correction:
            // If t3 != 0 then value >= B^3 > p, must subtract p once.
            // Else subtract p if t2..t0 >= p.
            let doSub := iszero(iszero(t3))

            if iszero(doSub) {
                let ge := 0
                if gt(t2, p2) { ge := 1 }
                if eq(t2, p2) {
                    if gt(t1, p1) { ge := 1 }
                    if eq(t1, p1) {
                        if iszero(lt(t0, p0)) { ge := 1 }
                    }
                }
                doSub := ge
            }

            if doSub {
                let bor := 0
                t0, bor := sbb(t0, p0, 0)
                t1, bor := sbb(t1, p1, bor)
                t2, bor := sbb(t2, p2, bor)
                // ignore bor: if it happens, it is covered by the implicit high limb (t3 was nonzero)
            }

            r0 := t0
            r1 := t1
            r2 := t2
        }
    }

    // wrappers
    function add(uint256[3] memory a, uint256[3] memory b) internal pure returns (uint256[3] memory r) {
        (r[0], r[1], r[2]) = add3(a[0], a[1], a[2], b[0], b[1], b[2]);
    }

    function sub(uint256[3] memory a, uint256[3] memory b) internal pure returns (uint256[3] memory r) {
        (r[0], r[1], r[2]) = sub3(a[0], a[1], a[2], b[0], b[1], b[2]);
    }

    function montMul(uint256[3] memory a, uint256[3] memory b) internal pure returns (uint256[3] memory r) {
        (r[0], r[1], r[2]) = montMul3(a[0], a[1], a[2], b[0], b[1], b[2]);
    }

    function montSqr(uint256[3] memory a) internal pure returns (uint256[3] memory r) {
        (r[0], r[1], r[2]) = montSqr3(a[0], a[1], a[2]);
    }

    function toMontgomery(uint256[3] memory x) internal pure returns (uint256[3] memory) {
        uint256[3] memory r2;
        r2[0] = R2_0; r2[1] = R2_1; r2[2] = R2_2;
        return montMul(x, r2);
    }

    function fromMontgomery(uint256[3] memory x) internal pure returns (uint256[3] memory) {
        uint256[3] memory one;
        one[0] = 1; one[1] = 0; one[2] = 0;
        return montMul(x, one);
    }
}