# Этап PC7: подробный технический отчет

## 0. Краткий итог

На текущем этапе завершен `Prod Core` новой архитектуры:

- тяжелые вычисления pairing (`Miller + final exponentiation`) выполняются off-chain,
- on-chain выполняется компактная криптографическая верификация relation-proof,
- контракт **не доверяет** передаваемому off-chain артефакту напрямую: корректность артефакта проверяется через proof и публичные входы,
- внедрен воспроизводимый pipeline итоговых измерений (`PC7`) и зафиксированы результаты.

Ключевой практический результат по газу:

1. legacy full on-chain single: `251,151,360` gas,
2. новая архитектура verify-single (e2e): `67,390` gas,
3. legacy full on-chain multi2: `286,582,809` gas,
4. новая архитектура packed multi verify (e2e): `58,513` gas.

Это соответствует снижению стоимости на ~`99.97%+` (порядки `10^8 -> 10^5`).

---

## 1. Контекст и постановка задачи этапа

### 1.1 Исходная проблема

Полное on-chain вычисление pairing на `MNT4-753` в EVM имеет стоимость порядка сотен миллионов газа. Даже после оптимизаций hot path это остается непрактично для mainnet и большинства L2-сценариев с жестким budget на calldata/compute.

### 1.2 Цель новой архитектуры

Перейти к модели:

- off-chain: вычислить pairing и построить трассу/свидетельство,
- on-chain: проверять компактное доказательство корректности relation между входами, артефактом и результатом.

Это соответствует целевой схеме `heavy compute off-chain -> compact verify on-chain`.

### 1.3 Что именно должен гарантировать on-chain verifier

Принимается только то, что подтверждено proof:

1. связь `statement` (fixedQ, points, context, epoch) с `output`,
2. связь `output` с `artifact` (trace/transcript commitments),
3. связь всего набора с доменом исполнения (`chainId`, `verifier`, `domainTag`, `nonce`, `validUntil`),
4. защита от replay и подмены packed-данных.

---

## 2. Формальная модель проверяемого объекта

Введем кортежи:

- `S` (statement):
  - `fixedQId`, `fixedQCommitment`, `pointsHash`, `context`, `pairs`, `epoch`.
- `O` (output):
  - `resultDigest`, `isValid`.
- `A` (artifact):
  - `artifactRoot`, `transcriptHash`, `epoch`, `validUntil`, `nonce`.
- `PI` (public inputs proof):
  - `statementHash`, `outputHash`, `artifactHash`,
  - `fixedQId`, `fixedQCommitment`, `pointsHash`, `context`,
  - `resultDigest`, `artifactRoot`, `transcriptHash`, `domainTag`,
  - `epoch`, `pairs`, `validUntil`, `nonce`, `chainId`, `verifier`.

Хеш публичных входов:

\[
\texttt{piHash} = H(PI)
\]

где `H` реализован как EVM `keccak256` по типизированному объекту (`PairingTraceProofTypes.PUBLIC_INPUTS_TYPEHASH`).

---

## 3. Что реализовано на уровне контрактов

## 3.1 Контракты и роли

1. [/Users/a.i.semenov/Desktop/diploma/src/PairingArtifactVerifierV2.sol](/Users/a.i.semenov/Desktop/diploma/src/PairingArtifactVerifierV2.sol)
- основной on-chain verifier для artifact/relation пути,
- собирает `PI`, вызывает backend `proofVerifier.verify(inputs, proof)`,
- поддерживает `verify` и `consume` режимы,
- реализует security guards и anti-replay.

2. [/Users/a.i.semenov/Desktop/diploma/src/Groth16TraceProofVerifier.sol](/Users/a.i.semenov/Desktop/diploma/src/Groth16TraceProofVerifier.sol)
- succinct backend,
- преобразует `PI` в массив из 17 public signals Fr(BN254),
- вызывает `Groth16Verifier.verifyProof(...)`.

3. [/Users/a.i.semenov/Desktop/diploma/src/PairingTraceProofTypes.sol](/Users/a.i.semenov/Desktop/diploma/src/PairingTraceProofTypes.sol)
- канонический формат и хеширование `PI`.

4. [/Users/a.i.semenov/Desktop/diploma/src/OffchainStackVerifierHarness.sol](/Users/a.i.semenov/Desktop/diploma/src/OffchainStackVerifierHarness.sol)
- тестовый/интеграционный harness,
- предоставляет удобные функции `computeHashes*`, `verify*`, `packMeta`, `packPairsFlags`.

5. [/Users/a.i.semenov/Desktop/diploma/src/FixedQRegistry.sol](/Users/a.i.semenov/Desktop/diploma/src/FixedQRegistry.sol)
- реестр активных `fixedQId -> coeffsCommitment`.

## 3.2 Критические функции `PairingArtifactVerifierV2`

### Verify-path

1. `verifyForPoints(...)`
- строит statement из массива точек,
- проверяет лимиты и согласование с registry,
- формирует `PI`, вызывает backend,
- возвращает `true/false` (malformed proof не должен ронять verify-path).

2. `verifySinglePacked(...)`
- packed single-point путь для минимизации calldata,
- `packedMeta = (epoch, artifactEpoch, validUntil, nonce)`,
- `packedFlags`: bit0=`isValid`.

3. `verifyPointsPacked(...)`
- packed multi путь,
- вместо массива точек передается `pointsHash`,
- `packedPairsFlags`: `[0..63]=pairs`, bit64=`isValid`.

### Consume-path

1. `consumeVerifiedForPoints(...)`
2. `consumeSinglePacked(...)`
3. `consumePointsPacked(...)`

Эти функции дополнительно:

- помечают attestation как consumed,
- помечают proof-nullifier как consumed,
- тем самым предотвращают replay на уровне state.

## 3.3 Security/hardening механизмы (актуальное состояние)

Реализованы:

1. `maxValidityWindow`, `maxPairs`, `maxProofBytes`.
2. `nullifierPolicy`:
   - `GLOBAL`,
   - `SENDER_SCOPED`.
3. строгая проверка fixedQ:
   - активность в registry,
   - совпадение `fixedQCommitment`.
4. `ArtifactExpired`, `ArtifactValidityTooLong`, `EpochMismatch`.
5. Packed flags guards (`BadPackedFlags`).
6. verify-path устойчив к malformed proof (`try/catch -> false`).

---

## 4. Что реализовано в relation-circuit

Файл:
- [/Users/a.i.semenov/Desktop/diploma/zk/stage6_groth16/stage6_input_binding.circom](/Users/a.i.semenov/Desktop/diploma/zk/stage6_groth16/stage6_input_binding.circom)

Схема содержит:

1. Public signals (17):
- `piHash, resultDigest, artifactRoot, transcriptHash, fixedQCommitment, pointsHash, context, epoch, pairs, domainTag, statementHash, outputHash, fixedQId, validUntil, nonce, chainId, verifierAddr`.

2. Private witness:
- trace digest слова (`millerDigest`, `singlesDigest`, `millerOut00`, ...),
- multi-путь (`pairMiller[8]`, `pairEnabled[8]`, `seed`),
- non-native anchor для `Fp(753)` (`millerOut00L`, `millerOut11L`, `qMulA`, `carryMulA`, `mulAOut`).

3. Constraint-блоки:

- ограничение `pairs <= 8`,
- булевость и prefix-структура `pairEnabled`,
- проверка non-native умножения `FpMulWithQuot` (через PC3 gadgets),
- aggregation constraint для `singlesDigest`,
- shared accumulator переходы `acc[i+1] = acc[i]^2 + lineTerm[i]`,
- constraint `resultDigest == finalState`,
- constraints для `transcriptHash` и `artifactRoot` как линейных комбинаций связанного состояния.

Смысл: proof связывает наблюдаемые on-chain данные с канонизированной off-chain трассой и переходами relation-модели.

---

## 5. Off-chain stack: как строится доказательство

Ключевые файлы:

1. [/Users/a.i.semenov/Desktop/diploma/script/stage6_offchain_stack.py](/Users/a.i.semenov/Desktop/diploma/script/stage6_offchain_stack.py)
2. [/Users/a.i.semenov/Desktop/diploma/script/generate_stage6_groth16_proof.py](/Users/a.i.semenov/Desktop/diploma/script/generate_stage6_groth16_proof.py)

Протокол (e2e):

1. Деплой локальной среды (`anvil`) и контрактов verifier-стека.
2. Получение канонического trace core из `PairingTraceWorker`.
3. Получение probe-слов Miller/FE witness.
4. Для multi режима: сбор `pairMiller[i]` и маски enabled.
5. Решение relation-модели и построение witness (`input.json`).
6. Генерация Groth16 proof.
7. On-chain verify через V2 verifier.
8. Сбор газа (`cast estimate`) и offchain time (`witnessBuildMs`, `proofBuildMs`).

---

## 6. Что именно добавлено на этапе PC7

## 6.1 Новый воспроизводимый pipeline

Файл:
- [/Users/a.i.semenov/Desktop/diploma/script/pc7_prod_core_pipeline.py](/Users/a.i.semenov/Desktop/diploma/script/pc7_prod_core_pipeline.py)

Функции pipeline:

1. optional build Groth16 (`--skip-build`),
2. stage6 e2e для `pairs=1/2/4/8` (`--skip-stage6` для кэша),
3. baseline gas extraction из legacy on-chain тестов,
4. new architecture unit gas extraction,
5. security suites прогон,
6. full regression (`forge test --offline`) опционально,
7. экспорт сводок:
   - [/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.json](/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.json)
   - [/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.md](/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.md)

## 6.2 Исправление корректности provenance в PC7

Исправлено поведение `--skip-stage6`:

- ранее `output` в summary мог указывать на целевой `pc7` путь даже при чтении из `pc6/pc5` cache,
- теперь summary фиксирует **фактический source file**.

Это важно для воспроизводимости и аудита результатов.

---

## 7. Методология измерений

## 7.1 Категории измерений

1. Legacy baseline (старый on-chain compute):
- тесты из `MNT4TatePairingV4.t.sol`.

2. New architecture e2e estimates:
- `stage6_offchain_stack.py --backend groth16 --verify`.

3. New architecture unit gas:
- `Groth16TraceProofVerifierTest`,
- `PairingArtifactVerifierV2Test`,
- `OffchainStackVerifierHarnessTest`.

4. Security/regression:
- security suites + полный `forge test --offline`.

## 7.2 Воспроизводимые команды

```bash
forge test --offline --match-contract Groth16Stage6VerifierTest
forge test --offline --match-contract Groth16TraceProofVerifierTest
forge test --offline --match-contract PairingArtifactVerifierV2Test
forge test --offline --match-contract OffchainStackVerifierHarnessTest
forge test --offline

python3 script/pc7_prod_core_pipeline.py --skip-build --skip-stage6 --full-regression
```

---

## 8. Результаты измерений

## 8.1 Legacy baseline (старый on-chain compute)

Источник: `cache/pc7_prod_core_summary.json`.

| Метрика | Газ |
|---|---:|
| onchainSingleFullWord | 251,151,360 |
| onchainSinglePreparedWord | 258,189,002 |
| onchainMulti2FullWord | 286,582,809 |
| onchainMulti2PreparedWord | 293,625,692 |

## 8.2 Новая архитектура: e2e (stage6, groth16)

Источник: `cache/stage6_offchain_witness_groth16_pc6_p{1,2,4,8}.json`, агрегировано в PC7 summary.

| pairs | verifySingleEstimate | verifySinglePackedEstimate | verifyPointsPackedEstimate | witnessBuildMs | proofBuildMs |
|---:|---:|---:|---:|---:|---:|
| 1 | 67,390 | 63,864 | - | 2,089 | 597 |
| 2 | 76,469 | - | 58,513 | 2,652 | 658 |
| 4 | 91,253 | - | 58,513 | 3,833 | 626 |
| 8 | 120,884 | - | 58,513 | 5,945 | 607 |

Интерпретация:

1. `verifySingleEstimate` растет с числом пар, так как путь включает больше данных statement/points.
2. `verifyPointsPackedEstimate` почти константен по `n`, т.к. on-chain передается уже `pointsHash`, а не массив точек.
3. `proofBuildMs` почти стабилен; основная зависимость по времени от `n` в witness-build.

## 8.3 Новая архитектура: unit snapshots

### Groth16 backend

Источник: `Groth16TraceProofVerifierTest`.

| Тест | Газ |
|---|---:|
| validFixture (pairs=1) | 309,013 |
| validFixturePairs2 | 308,711 |
| validFixturePairs4 | 308,903 |
| validFixturePairs8 | 309,041 |

Замечание: это стоимость backend-proof проверки как отдельного юнита; e2e verify-путь ниже, так как вызываются другие интерфейсы/пути и используется `cast estimate` на конкретном вызове verifier-контура.

### Artifact verifier (V2)

Источник: `PairingArtifactVerifierV2Test`.

| Тест | Газ |
|---|---:|
| verifyForPoints_valid | 85,544 |
| verifySinglePacked_valid | 85,140 |
| verifyPointsPacked_multi2_valid | 100,874 |
| consumeVerifiedForPoints_replayReverts | 155,000 |
| consumePointsPacked_replayReverts | 166,077 |

### Harness

Источник: `OffchainStackVerifierHarnessTest`.

| Тест | Газ |
|---|---:|
| verifySingle_valid | 101,981 |
| verifySinglePacked_valid | 98,599 |
| verifyPointsPacked_multi2_valid | 126,414 |

## 8.4 Security matrix и regression

Из `cache/pc7_prod_core_summary.json`:

- `Groth16TraceProofVerifierTest`: `10 passed, 0 failed`.
- `PairingArtifactVerifierV2Test`: `17 passed, 0 failed`.
- `OffchainStackVerifierHarnessTest`: `4 passed, 0 failed`.

Полный regression:

- `18 suites`,
- `223 passed, 0 failed, 0 skipped`.

---

## 9. Сравнение старой и новой архитектуры (по ключевым сценариям)

### 9.1 Single

\[
\text{speedup}_{single} = \frac{251{,}151{,}360}{67{,}390} \approx 3726.83\times
\]

Снижение газа: ~`99.973%`.

### 9.2 Multi2

\[
\text{speedup}_{multi2} = \frac{286{,}582{,}809}{58{,}513} \approx 4897.76\times
\]

Снижение газа: ~`99.980%`.

Практический вывод: задача вычисления pairing как on-chain compute заменена на задачу succinct verification с радикально меньшей on-chain ценой.

---

## 10. Особенности реализации, важные для корректной интерпретации

1. Новая архитектура по-прежнему остается про `MNT4`-pairing relation (канонический trace worker и соответствующие witness-поля), но on-chain криптографический backend верификации реализован как `Groth16 over BN254 precompile`.
2. Контракт не доверяет переданному artifact/cache напрямую: доверяется только soundness proof backend и корректности публичных входов.
3. Packed multi путь (`verifyPointsPacked`) является критическим для снижения on-chain стоимости при росте числа пар.
4. `consume*` пути дороже `verify*` из-за state write (anti-replay записи).
5. Для тестов есть deterministic/mock ветки с большими gas-значениями; production-целевая ветка на данном этапе — succinct backend.

---

## 11. Ограничения и остаточные задачи после PC7

`Prod Core` закрыт, но для исследовательского трека остаются:

1. folding/recursive aggregation (масштабирование batch verify),
2. расширение relation-circuit к более строгим non-native переходам,
3. дополнительные proof-system бэкенды и сравнительный анализ,
4. более широкая performance-модель (включая off-chain CPU/RAM/latency профилирование на длинных batch).

---

## 12. Список ключевых артефактов этапа

1. Отчет этапа:
- [/Users/a.i.semenov/Desktop/diploma/PC7_IMPLEMENTATION_REPORT.md](/Users/a.i.semenov/Desktop/diploma/PC7_IMPLEMENTATION_REPORT.md)

2. Новый подробный отчет (этот документ):
- [/Users/a.i.semenov/Desktop/diploma/PC7_DETAILED_STAGE_REPORT.md](/Users/a.i.semenov/Desktop/diploma/PC7_DETAILED_STAGE_REPORT.md)

3. Pipeline и итоговые сводки:
- [/Users/a.i.semenov/Desktop/diploma/script/pc7_prod_core_pipeline.py](/Users/a.i.semenov/Desktop/diploma/script/pc7_prod_core_pipeline.py)
- [/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.json](/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.json)
- [/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.md](/Users/a.i.semenov/Desktop/diploma/cache/pc7_prod_core_summary.md)

4. Основные контракты этапа:
- [/Users/a.i.semenov/Desktop/diploma/src/PairingArtifactVerifierV2.sol](/Users/a.i.semenov/Desktop/diploma/src/PairingArtifactVerifierV2.sol)
- [/Users/a.i.semenov/Desktop/diploma/src/Groth16TraceProofVerifier.sol](/Users/a.i.semenov/Desktop/diploma/src/Groth16TraceProofVerifier.sol)
- [/Users/a.i.semenov/Desktop/diploma/src/PairingTraceProofTypes.sol](/Users/a.i.semenov/Desktop/diploma/src/PairingTraceProofTypes.sol)
- [/Users/a.i.semenov/Desktop/diploma/src/OffchainStackVerifierHarness.sol](/Users/a.i.semenov/Desktop/diploma/src/OffchainStackVerifierHarness.sol)

5. Off-chain stack/circuit:
- [/Users/a.i.semenov/Desktop/diploma/script/stage6_offchain_stack.py](/Users/a.i.semenov/Desktop/diploma/script/stage6_offchain_stack.py)
- [/Users/a.i.semenov/Desktop/diploma/script/generate_stage6_groth16_proof.py](/Users/a.i.semenov/Desktop/diploma/script/generate_stage6_groth16_proof.py)
- [/Users/a.i.semenov/Desktop/diploma/zk/stage6_groth16/stage6_input_binding.circom](/Users/a.i.semenov/Desktop/diploma/zk/stage6_groth16/stage6_input_binding.circom)
