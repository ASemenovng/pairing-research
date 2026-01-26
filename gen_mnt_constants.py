# # gen_mnt_constants.py

# # Параметры кривой MNT4-753 (Base Field Modulus)
# # Взято из стандартных параметров (libsnark / Coda / Mina)
# # P = (q для MNT6)
# P_HEX = "01C4C62D92C41110229022EE98E97DD8787C9D79DF4753733A7C786E3C0F108169996F8942A8C5704E90B03079237D304197E690B81005C8817AF031317E3CB0C8360D759F9F42490F4F2468249629CB9735467F547228308D0A1389D39077977A7790D4D36315570D"

# P = int(P_HEX, 16)
# MASK_256 = 2**256
# R = 2**(256 * 3)  # R = 2^768 (так как у нас 3 лимба по 256 бит)

# # 1. R^2 mod P
# R_squared = (R * R) % P

# # 2. MAGIC = -P^(-1) mod 2^256
# invP = pow(P, -1, MASK_256)
# MAGIC = (MASK_256 - invP) % MASK_256

# def split_3_limbs(val):
#     l0 = val & (MASK_256 - 1)
#     val >>= 256
#     l1 = val & (MASK_256 - 1)
#     val >>= 256
#     l2 = val & (MASK_256 - 1)
#     return hex(l0), hex(l1), hex(l2)

# p0, p1, p2 = split_3_limbs(P)
# r0, r1, r2 = split_3_limbs(R_squared)

# print(f"// MNT4-753 Constants")
# print(f"uint256 private constant P_0  = {p0};")
# print(f"uint256 private constant P_1  = {p1};")
# print(f"uint256 private constant P_2  = {p2};")
# print(f"")
# print(f"uint256 private constant R2_0 = {r0};")
# print(f"uint256 private constant R2_1 = {r1};")
# print(f"uint256 private constant R2_2 = {r2};")
# print(f"")
# print(f"uint256 private constant MAGIC = {hex(MAGIC)};")

# gen_mnt_constants.py

# Правильный модуль MNT4-753 (из arkworks-rs / Mina)
P_HEX = "01C4C62D92C41110229022EEE2CDADB7F997505B8FAFED5EB7E8F96C97D87307FDB925E8A0ED8D99D124D9A15AF79DB117E776F218059DB80F0DA5CB537E38685ACCE9767254A4638810719AC425F0E39D54522CDD119F5E9063DE245E8001"

P = int(P_HEX, 16)
MASK_256 = 2**256
R = 2**(256 * 3)  # R = 2^768

# Проверка на простоту (для уверенности)
def is_prime(n, k=5):
    if n < 2: return False
    if n == 2 or n == 3: return True
    if n % 2 == 0: return False
    r, s = 0, n - 1
    while s % 2 == 0:
        r += 1
        s //= 2
    for _ in range(k):
        a = 2 + _
        x = pow(a, s, n)
        if x == 1 or x == n - 1:
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True

print(f"P is prime: {is_prime(P)}")
print(f"P bit length: {P.bit_length()}") # Должно быть 753

# 1. R^2 mod P
R_squared = (R * R) % P

# 2. MAGIC
invP = pow(P, -1, MASK_256)
MAGIC = (MASK_256 - invP) % MASK_256

def split_3_limbs(val):
    l0 = val & (MASK_256 - 1)
    val >>= 256
    l1 = val & (MASK_256 - 1)
    val >>= 256
    l2 = val & (MASK_256 - 1)
    return hex(l0), hex(l1), hex(l2)

p0, p1, p2 = split_3_limbs(P)
r0, r1, r2 = split_3_limbs(R_squared)

print(f"\n// MNT4-753 Constants")
print(f"uint256 private constant P_0  = {p0};")
print(f"uint256 private constant P_1  = {p1};")
print(f"uint256 private constant P_2  = {p2};")
print(f"")
print(f"uint256 private constant R2_0 = {r0};")
print(f"uint256 private constant R2_1 = {r1};")
print(f"uint256 private constant R2_2 = {r2};")
print(f"")
print(f"uint256 private constant MAGIC = {hex(MAGIC)};")