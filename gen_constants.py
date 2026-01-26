# gen_constants.py

# BLS12-381 Base Field Modulus
P = 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab

# Наша архитектура: 2 слова по 256 бит
MASK_256 = 2**256
R = 2**512  # R = (2^256)^2

# 1. Вычисляем R^2 mod P
R_squared = (R * R) % P

# 2. Вычисляем MAGIC = -P^(-1) mod 2^256
# Это число, которое при умножении на P дает -1 (по модулю 2^256)
invP = pow(P, -1, MASK_256)
MAGIC = (MASK_256 - invP) % MASK_256

# Разбиваем P и R2 на части для Solidity
def split(val):
    lo = val & (MASK_256 - 1)
    hi = val >> 256
    return hex(lo), hex(hi)

p_lo, p_hi = split(P)
r2_lo, r2_hi = split(R_squared)

print("// Вставь эти константы в BigIntFp.sol:")
print(f"uint256 private constant P_LO  = {p_lo};")
print(f"uint256 private constant P_HI  = {p_hi};")
print(f"uint256 private constant R2_LO = {r2_lo};")
print(f"uint256 private constant R2_HI = {r2_hi};")
print(f"uint256 private constant MAGIC = {hex(MAGIC)};")