# gen_mnt_ext.py
import sys

# MNT4-753 Modulus
P_HEX = "01C4C62D92C41110229022EEE2CDADB7F997505B8FAFED5EB7E8F96C97D87307FDB925E8A0ED8D99D124D9A15AF79DB117E776F218059DB80F0DA5CB537E38685ACCE9767254A4638810719AC425F0E39D54522CDD119F5E9063DE245E8001"
P = int(P_HEX, 16)

MASK_256 = 2**256
R = 2**(256 * 3) # R = 2^768

# Quadratic Non-Residue for Fp2 construction
# Fp2 = Fp[u] / (u^2 - 13)
BETA = 13

# Convert Beta to Montgomery form: Beta * R mod P
BETA_MONT = (BETA * R) % P

def split_3_limbs(val):
    l0 = val & (MASK_256 - 1)
    val >>= 256
    l1 = val & (MASK_256 - 1)
    val >>= 256
    l2 = val & (MASK_256 - 1)
    return hex(l0), hex(l1), hex(l2)

b0, b1, b2 = split_3_limbs(BETA_MONT)

print("-" * 60)
print(f"// Constants for MNT4Extension.sol")
print(f"// BETA_MONT = 13 * R mod P")
print(f"uint256 private constant BETA_MONT_0 = {b0};")
print(f"uint256 private constant BETA_MONT_1 = {b1};")
print(f"uint256 private constant BETA_MONT_2 = {b2};")
print("-" * 60)

# Optional: Verify QNR properties
def is_qnr(val, p):
    return pow(val, (p - 1) // 2, p) != 1

print(f"Verification:")
print(f"Is {BETA} a QNR in Fp? {is_qnr(BETA, P)}")
# For Fp4, we use xi = u. Valid if norm(u) = -beta is QNR in Fp.
norm_u = (-BETA) % P
print(f"Is u (root of {BETA}) valid for Fp4? {is_qnr(norm_u, P)}")