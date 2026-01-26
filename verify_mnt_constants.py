# verify_mnt_constants.py

# Параметры MNT4-753
P_HEX = "01C4C62D92C41110229022EE98E97DD8787C9D79DF4753733A7C786E3C0F108169996F8942A8C5704E90B03079237D304197E690B81005C8817AF031317E3CB0C8360D759F9F42490F4F2468249629CB9735467F547228308D0A1389D39077977A7790D4D36315570D"

P = int(P_HEX, 16)
print(f"P = {hex(P)}")
print(f"P bit length: {P.bit_length()}")

MASK_256 = 2**256
R = 2**(256 * 3)  # R = 2^768

# Проверяем R^2 mod P
R_squared = (R * R) % P
print(f"\nR^2 mod P = {hex(R_squared)}")

# Проверяем MAGIC
invP = pow(P, -1, MASK_256)
MAGIC = (MASK_256 - invP) % MASK_256
print(f"\nMAGIC = {hex(MAGIC)}")

# Проверяем корректность MAGIC
test = (P * MAGIC) % MASK_256
expected = (MASK_256 - 1)  # Должно быть -1 mod 2^256
print(f"\nP * MAGIC mod 2^256 = {hex(test)}")
print(f"Expected (2^256 - 1) = {hex(expected)}")
print(f"MAGIC correct: {test == expected}")

# Разбиваем на лимбы
def split_3_limbs(val):
    l0 = val & (MASK_256 - 1)
    val >>= 256
    l1 = val & (MASK_256 - 1)
    val >>= 256
    l2 = val & (MASK_256 - 1)
    return l0, l1, l2

p0, p1, p2 = split_3_limbs(P)
r0, r1, r2 = split_3_limbs(R_squared)

print(f"\n=== P limbs ===")
print(f"P_0 = {hex(p0)}")
print(f"P_1 = {hex(p1)}")
print(f"P_2 = {hex(p2)}")

print(f"\n=== R^2 limbs ===")
print(f"R2_0 = {hex(r0)}")
print(f"R2_1 = {hex(r1)}")
print(f"R2_2 = {hex(r2)}")

# Проверяем восстановление P
P_reconstructed = p0 + (p1 << 256) + (p2 << 512)
print(f"\nP reconstructed correctly: {P == P_reconstructed}")

# Тест Монтгомери вручную
print("\n=== Manual Montgomery Test ===")
a = 2
b = 3

# Конвертируем в Монтгомери
a_mont = (a * R) % P
b_mont = (b * R) % P

print(f"a = {a}")
print(f"b = {b}")
print(f"a_mont = {hex(a_mont)}")
print(f"b_mont = {hex(b_mont)}")

# Умножение в Монтгомери
# montMul(a_mont, b_mont) должно дать (a*b)_mont
ab_mont_expected = (a * b * R) % P
print(f"Expected (a*b)_mont = {hex(ab_mont_expected)}")

# Обратное преобразование
ab = (ab_mont_expected * pow(R, -1, P)) % P
print(f"Expected a*b = {ab}")

# Альтернативный способ: toMontgomery использует montMul(x, R^2)
# montMul(x, R^2) = (x * R^2 * R^-1) mod P = (x * R) mod P ✓
a_mont_via_mul = (a * R_squared * pow(R, -1, P)) % P
print(f"\na_mont via montMul(a, R^2) = {hex(a_mont_via_mul)}")
print(f"Matches direct a*R: {a_mont == a_mont_via_mul}")