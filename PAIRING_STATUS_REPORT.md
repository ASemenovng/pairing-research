# PAIRING_STATUS_REPORT

Дата обновления: 6 марта 2026

## 1. Executive Summary

Проект реализует две большие ветки архитектуры:

- `A. Полный on-chain pairing` на MNT4-753 (два режима внутри: `fixed-Q prepared` и `full on-chain line generation`).
- `B. Новая архитектура verify-vs-compute` (R4 -> R8 -> R5): тяжелая арифметика off-chain, on-chain только проверка компактных attestations/claims.

Ключевой практический вывод по газу:

- Полный on-chain pairing остается очень дорогим (десятки/сотни миллионов газа в текущих benchmark-конфигурациях).
- Новая архитектура (R4/R8/R5) уже дает стоимость on-chain проверки в диапазоне десятков/сотен тысяч газа вместо десятков/сотен миллионов.

Это и есть основная практическая траектория для диссертационной версии: сохранить математическую корректность pairing-пайплайна, но вынести тяжелые вычисления off-chain и оставить on-chain только криптографически проверяемую валидацию результата.

---

## 2. Исследовательская идея и постановка задачи

### 2.1. Исходная цель

Изначальная цель работы: реализовать on-chain Tate/Ate pairing на кривой MNT4-753 в EVM и минимизировать стоимость газа до практически применимого уровня.

### 2.2. Научная проблема

Для MNT4-753 нет отдельного precompile в Ethereum, поэтому:

- вся арифметика `Fp/Fq2/Fq4` исполняется обычным EVM-кодом;
- стоимость складывается из тысяч/десятков тысяч больших операций (Montgomery mul/sqr, расширения поля, Miller+final exp);
- прямой on-chain compute-path системно дорогой.

### 2.3. Как проект отвечает на проблему

Проект разделен на две части:

1. `On-chain compute baseline`:
- строгая реализация pairing и инженерная оптимизация hot-path;
- формальная/эмпирическая оценка стоимости;
- демонстрация предела применимости полного on-chain вычисления.

2. `On-chain verify architecture`:
- вычисление pairing и/или агрегации переносится off-chain;
- on-chain верифицируется компактное доказательство/аттестация корректности результата;
- достигается practically deployable gas profile.

---

## 3. Математическая основа реализации

### 3.1. Поля и представления

Используется башня:

- `Fp` (модуль MNT4-753, 3 limb по 256 бит в Montgomery-домене)
- `Fq2 = Fp[u]/(u^2-13)`
- `Fq4 = Fq2[v]/(v^2-u)`

Выбранный memory layout:

- `Fp`: 3 words
- `Fq2`: 6 words (`c0[3], c1[3]`)
- `Fq4`: 12 words (`c0(Fq2), c1(Fq2)`)

### 3.2. Miller loop в проекте

Используется зашитый loop encoding `ATE_LOOP_ENC`:

- длина массива: `377` шагов (см. `sparsePreparedLoopLenProbe`)
- фактические doubling-итерации: `L = 376` (проход с индекса 1)
- ненулевые add-итерации по loop digits: `123`
- + `1` коррекция для отрицательного loop count (`ATE_IS_LOOP_COUNT_NEG = true`)

Итого в полном раунде получается эквивалент `124` add-переходов для bounded/full benchmark-модели.

### 3.3. Denominator elimination

В Miller path инверсия не выполняется на каждом шаге: используется denominator elimination и коррекция переносится в final exponentiation (с учетом отрицательного loop count). Это принципиально снижает стоимость hot-loop.

### 3.4. Final exponentiation

Реализация использует фиксированную цепочку для hard-part (`W0_CHAIN_W5`) и cyclotomic/Frobenius-примитивы в pointer path, а не универсальный bit-by-bit exponentiation в production path.

---

## 4. Почему выбраны именно эти инженерные решения

### 4.1. Fixed-Q режим

`G2`-точки в verifier-практике обычно фиксированы (VK/параметры). Значит можно precompute line coefficients и существенно разгрузить on-chain часть. Это основной индустриальный режим.

### 4.2. Montgomery vs альтернативы

Текущий выбор: Montgomery reduction (`montMul3`, `montSqr3`) как базовый движок `Fp`.

Альтернативы, которые релевантны для сравнения в исследовательской части:

- Barrett reduction
- Comba/Schoolbook с отдельным редьюсом
- CIOS/FIOS вариации Montgomery
- lazy-reduction стратегии с отложенным `reduce3`

Почему Montgomery сейчас базовый:

- устойчиво минимизирует стоимость модульного редьюса на EVM для 753-битного модуля;
- хорошо сочетается с pointer/scratch архитектурой;
- используется большинством production-grade big-int ядeр в EVM-контексте для больших модулей.

### 4.3. Sparse-by-line

Линии Miller шага кодируются разреженно:

- doubling: `3 x Fq2`
- addition: `2 x Fq2`

Плюс используется специализированное умножение на линию (`_fq4MulByLinePtrTo` / fused варианты), чтобы не платить цену общего dense `fq4Mul` на каждом раунде.

### 4.4. Pointer/scratch API

Критический hot-path реализован как `*To(ptrOut, ptrA, ptrB, scratch)` без dynamic allocations в цикле Miller. Это ключевая предпосылка для газ-оптимизации.

### 4.5. Streaming coeff loading

Поддержаны два канала prepared данных:

- bytes blob (`memory/calldata`)
- code shards через `EXTCODECOPY`

Это делает возможным экспериментировать с компромиссом `storage/calldata/code` без изменения ядра арифметики.

---

## 5. Полная архитектура: старая и новая

### 5.1. Старая архитектура (compute on-chain)

Режимы:

- `fixed-Q prepared`: coefficients precomputed и подаются в Miller.
- `full on-chain`: coefficients генерируются в Jacobian/mixed шагах прямо в loop.

Общий pipeline:

1. (опционально) `prepareFixedQBlobSparse`
2. Miller loop
3. Final exponentiation

### 5.2. Новая архитектура (verify on-chain)

Слои:

- `R4 PairingRelationVerifier`: on-chain проверка подписи/доказательства для statement/output (без on-chain pairing compute).
- `R8 PairingArtifactVerifier`: добавляет проверку artifact-пакета (epoch, expiry, transcript/artifact hashes, commitment binding, consume/replay protection).
- `R5 FoldingVerifier`: агрегация множества attestations в bundle + Merkle claim verification/consumption.

Это не отменяет старый compute-код, а добавляет practically viable execution path.

---

## 6. Подробный обзор контрактов и функций (без helper/debug)

Примечание: ниже перечислены операционные и API-функции. Вспомогательные `private` utility-функции вида `_load*`, `_store*`, `_ptr*`, `_debug*` и т.п. сознательно не детализируются как "helper".

## 6.1. `src/BigIntMNT.sol`

### Назначение

Базовая арифметика `Fp` (3-limb, Montgomery).

### Основные функции

- `add3NR(uint256,uint256,uint256,uint256,uint256,uint256)`
  Безусловное no-reduce сложение с переносом.
- `reduce3(uint256,uint256,uint256)`
  Приведение в канонический диапазон `[0, p)`.
- `reduce3Wide16(uint256,uint256,uint256)`
  Расширенный редьюс для накопленных intermediate значений.
- `mulBy13(uint256,uint256,uint256)`
  Умножение элемента `Fp` на константу 13.
- `add3(...)`
  Модульное сложение в `Fp`.
- `sub3(...)`
  Модульное вычитание в `Fp`.
- `montMul3(...)`
  Montgomery multiplication (3x3 limbs + редукция).
- `montSqr3(...)`
  Montgomery squaring.
- `toMontgomery3(...)`
  Перевод в Montgomery-домен.
- `fromMontgomery3(...)`
  Выход из Montgomery-домена.
- `inv3NativeStack(...)`
  Native inversion backend (stack-oriented path).
- `inv3Native(...)`
  Обертка нативной инверсии.
- `_modexp96(...)`
  Вызов precompile `0x05` для modexp.
- `inv3Modexp(...)`
  Инверсия через modexp backend.
- `inv3ByBackend(...)`
  Выбор backend для inversion.
- `inv3(...)`
  Унифицированный inversion API.
- Memory-wrapper слой: `add/sub/montMul/montSqr/inv/...`
  Совместимость и тестовые адаптеры.

## 6.2. `src/MNT4Extension.sol` (+ `MNT4ExtensionFinal`)

### Назначение

Арифметика `Fq2/Fq4` на pointer API, плюс struct-совместимость.

### Pointer API (`MNT4Extension`)

`Fq2`:

- `fq2AddTo`, `fq2AddNRTo`, `fq2ReduceTo`, `fq2SubTo`, `fq2NegTo`
- `fq2MulTo`
- `fq2SqrTo`
- `fq2MulByUTo`
- `fq2MulByFp3To`
- `fq2InvTo`, `fq2InvToModexp`, `fq2InvToByBackend`

`Fq4`:

- `fq4AddTo`, `fq4AddNRTo`, `fq4ReduceTo`, `fq4SubTo`
- `fq4MulByVTo`
- `fq4MulTo`
- `fq4SqrTo`
- `fq4MulByFq2To`
- `fq4InvTo`, `fq4InvToModexp`, `fq4InvToByBackend`

### Compatibility API (`MNT4ExtensionFinal`)

Struct-обертки над pointer ядром:

- `fq2Add/Sub/Mul/Sqr/MulByU/MulByFp/Inv`
- `fq4Add/Sub/Mul/Sqr/MulByFq2/MulByV/Inv`
- To/From backend wrappers для inversion.

## 6.3. `src/MNT4TatePairingArithmetic.sol`

### Назначение

Reference-слой group-операций и базовых pairing-операций для тестирования/сверки.

### Основные функции

- `g1AddAffine(G1Point,G1Point)`
- `g1DoubleAffine(G1Point,uint256[3])`
- `g2AddAffine(G2Point,G2Point)`
- `g2DoubleAffine(G2Point,Fq2)`
- `millerAccumulate(Fq4 f, Fq4 ell)`
  Reference `f <- f^2 * ell`.
- `fq4Pow(Fq4 x, uint256 e, ...)`
  Универсальный pow (reference/test utility).

## 6.4. `src/MNT4TatePairing.sol`

### Назначение

Главная библиотека pairing: подготовка coeffs, Miller loops, final exponentiation, single/multi APIs, memory/code-shards paths.

### Ключевые "боевые" функции

Prepared data:

- `prepareFixedQBlobSparse()`

Miller (prepared, memory blob):

- `millerLoopFixedQPreparedSparseBlobNoInv(...)`
- `multiMillerLoopFixedQPreparedSparseBlobNoInv(...)`
- `millerLoopFixedQPreparedSparseBlobNoInvMem(...)`
- `millerLoopFixedQPreparedSparseBlobNoInvMemDigest(...)`
- `multiMillerLoopFixedQPreparedSparseBlobNoInvMem(...)`
- `multiMillerLoopFixedQPreparedSparseBlobNoInvMemDigest(...)`
- `millerSinglesProductFixedQPreparedSparseBlobNoInvMem(...)`
- `millerSinglesProductFixedQPreparedSparseBlobNoInvMemDigest(...)`

Miller (prepared, code shards / EXTCODECOPY):

- `millerLoopFixedQPreparedSparseCodeShardsNoInvMem(...)`
- `millerLoopFixedQPreparedSparseCodeShardsNoInvMemDigest(...)`
- `multiMillerLoopFixedQPreparedSparseCodeShardsNoInvMem(...)`
- `multiMillerLoopFixedQPreparedSparseCodeShardsNoInvMemDigest(...)`

Miller (on-chain line generation):

- `millerLoopFixedQOnchainNoInvMem(...)`
- `millerLoopFixedQOnchainNoInvMemDigest(...)`
- `multiMillerLoopFixedQOnchainNoInvMem(...)`
- `multiMillerLoopFixedQOnchainNoInvMemDigest(...)`
- `millerSinglesProductFixedQOnchainNoInvMemDigest(...)`

Final exponentiation:

- `finalExponentiationFromMiller(Fq4 m, bool isLoopCountNeg)`

Top-level pairing APIs:

- `tatePairingFixedQPreparedSparse(...)`
- `tatePairingFixedQPreparedSparseDigest(...)`
- `tatePairingFixedQPreparedSparseMem(...)`
- `tatePairingFixedQPreparedSparseMemWord(...)`
- `tatePairingFixedQPreparedSparseMemDigest(...)`
- `tatePairingFixedQPreparedSparseCodeShardsMem(...)`
- `tatePairingFixedQPreparedSparseCodeShardsMemWord(...)`
- `tatePairingFixedQPreparedSparseCodeShardsMemDigest(...)`
- `tateMultiPairingFixedQPreparedSparse(...)`
- `tateMultiPairingFixedQPreparedSparseDigest(...)`
- `tateMultiPairingFixedQPreparedSparseSinglesProductDigest(...)`
- `tateMultiPairingFixedQPreparedSparseMem(...)`
- `tateMultiPairingFixedQPreparedSparseMemWord(...)`
- `tateMultiPairingFixedQPreparedSparseMemDigest(...)`
- `tateMultiPairingFixedQPreparedSparseCodeShardsMem(...)`
- `tateMultiPairingFixedQPreparedSparseCodeShardsMemWord(...)`
- `tateMultiPairingFixedQPreparedSparseCodeShardsMemDigest(...)`
- `tateMultiPairingFixedQPreparedSparseSinglesProductMem(...)`
- `tateMultiPairingFixedQPreparedSparseSinglesProductMemDigest(...)`
- `tatePairingFixedQOnchainMem(...)`
- `tatePairingFixedQOnchainMemWord(...)`
- `tatePairingFixedQOnchainMemDigest(...)`
- `tateMultiPairingFixedQOnchainMem(...)`
- `tateMultiPairingFixedQOnchainMemWord(...)`
- `tateMultiPairingFixedQOnchainMemDigest(...)`
- `tateMultiPairingFixedQOnchainSinglesProductMem(...)`
- `tateMultiPairingFixedQOnchainSinglesProductMemDigest(...)`

Core internal kernels (не helper):

- `_lineDoubleSparsePtrTo`
- `_lineAddSparsePtrTo`
- `_fq4MulByLinePtrTo`
- `_lineDoubleSparseMulPtrTo`
- `_lineAddSparseMulPtrTo`
- `_doublingStep`
- `_mixedAdditionStep`
- `_fq4CyclotomicSquarePtrTo`
- `_fq4CyclotomicMulPtrTo`
- `_finalExponentiationFromMillerPtrTo`
- `_expW0PtrTo`

## 6.5. `src/FixedQRegistry.sol`

- `transferOwnership(address)`
- `registerFixedQ(bytes32 fixedQId, bytes32 coeffsCommitment)`
- `updateCommitment(bytes32 fixedQId, bytes32 coeffsCommitment)`
- `setActive(bytes32 fixedQId, bool active)`
- `isRegistered(bytes32)`
- `isActive(bytes32)`
- `getEntry(bytes32)`

Функции управляют реестром `fixedQId -> commitment + status`.

## 6.6. `src/PairingStatementTypes.sol`

- `hashStatement(PairingStatement,uint256 chainId,address verifier)`
- `hashOutput(PairingOutput)`

Типизированные hash-функции для R4 statement/output.

## 6.7. `src/PairingArtifactTypes.sol`

- `hashStatement(PairingStatement,uint256 chainId,address verifier)`
- `hashOutput(PairingOutput)`
- `hashArtifact(PairingArtifact)`

Типизированные hash-функции для R8 artifact path.

## 6.8. `src/ECDSAAttestationVerifier.sol`

- `transferOwnership(address)`
- `setSigner(address)`
- `computeDigest(bytes32 statementHash, bytes32 outputHash)`
- `verify(bytes32 statementHash, bytes32 outputHash, bytes proof)`

Single-signer backend для R4.

## 6.9. `src/QuorumECDSAAttestationVerifier.sol`

- `transferOwnership(address)`
- `setSigner(address,bool)`
- `setQuorum(uint16)`
- `computeDigest(bytes32 statementHash, bytes32 outputHash, bytes32 artifactHash)`
- `verify(bytes32 statementHash, bytes32 outputHash, bytes32 artifactHash, bytes proof)`

Quorum ECDSA backend для R8.

## 6.10. `src/QuorumECDSABundleVerifier.sol`

- `transferOwnership(address)`
- `setSigner(address,bool)`
- `setQuorum(uint16)`
- `computeDigest(bytes32 bundleHash)`
- `verify(bytes32 bundleHash, bytes proof)`

Quorum ECDSA backend для R5 bundle подтверждений.

## 6.11. `src/PairingRelationVerifier.sol` (R4)

- `transferOwnership(address)`
- `setProofVerifier(IPairingProofVerifier)`
- `hashPoints(G1Affine[])`
- `statementHashForPoints(bytes32 fixedQId, G1Affine[] points, bytes32 context, uint64 epoch)`
- `outputHash(PairingOutput)`
- `verifyStatement(PairingStatement, PairingOutput, bytes proof)`
- `verifyForPoints(bytes32 fixedQId, G1Affine[] points, bytes32 context, uint64 epoch, PairingOutput, bytes proof)`

Смысл: on-chain проверяет подпись/доказательство согласованности `statementHash + outputHash`, не считая pairing on-chain.

## 6.12. `src/PairingArtifactVerifier.sol` (R8)

- `transferOwnership(address)`
- `setProofVerifier(IPairingArtifactProofVerifier)`
- `hashPoints(G1Affine[])`
- `statementHashForPoints(...)`
- `outputHash(PairingOutput)`
- `artifactHash(PairingArtifact)`
- `attestationId(bytes32 statementHash, bytes32 outputHash, bytes32 artifactHash)`
- `verifyForPoints(...)`
- `verifyStatement(...)`
- `consumeVerifiedForPoints(...)`
- `consumeVerifiedStatement(...)`

Добавляет artifact-level binding (`fixedQ commitment`, epoch, validUntil, transcript/artifact roots) и replay protection через `consumedAttestations`.

## 6.13. `src/FoldingVerifier.sol` (R5)

- `transferOwnership(address)`
- `setBundleProofVerifier(IBundleProofVerifier)`
- `hashPoints(G1Affine[])`
- `bundleHash(AggregateBundle)`
- `submitAggregateBundle(AggregateBundle bundle, bytes proof)`
- `attestationId(bytes32 statementHash, bytes32 outputHash, bytes32 artifactHash)`
- `claimLeaf(bytes32 attestationId)`
- `verifyClaimForPoints(...)`
- `consumeClaimForPoints(...)`

Смысл: пакетная агрегация claim'ов через Merkle root + on-chain verify/consume отдельного claim без полного recompute.

## 6.14. Интерфейсы

- `IPairingProofVerifier.verify(statementHash, outputHash, proof)`
- `IPairingArtifactProofVerifier.verify(statementHash, outputHash, artifactHash, proof)`
- `IBundleProofVerifier.verify(bundleHash, proof)`

---

## 7. Что именно оптимизировано и в каком статусе

## 7.1. Оптимизации compute-path (без смены архитектуры)

Реализовано:

- `R7` unified streaming-load layer (`Fp3/Fq2/Fq4` loaders, code-shards path)
- `R1` packed prepared fixed-Q sparse format
- `R3` fused line-eval + mulByLine в hot path
- `R2` shared Miller accumulator (один `f^2` на раунд для multi)
- перенос инверсии из Miller в FE (denominator elimination + FE correction)
- loop digits в `bytes` (`ATE_LOOP_ENC`), без `uint256[] constant` в loop
- fixed-chain FE (`W0_CHAIN_W5`) вместо общего bitwise pow в production path

Отложено/не критично для текущего этапа:

- `R6` membership-test specific path (не нужен в текущем протоколе)

## 7.2. Архитектурные оптимизации

Реализовано:

- `R4` relation verifier (`PairingRelationVerifier`)
- `R8` artifact-aware verifier (`PairingArtifactVerifier`)
- `R5` folding/aggregation verifier (`FoldingVerifier`)

В работе на уровне диссертации/методологии:

- `R9` финализация формальной модели + полная сравнительная экспериментальная глава.

---

## 8. Методология тестирования

## 8.1. Принципы

Тестирование разделено на 4 уровня:

1. `Алгебраическая корректность`
- BigInt (`add/sub/mul/sqr/inv`, Montgomery roundtrip)
- Extension (`fq2/fq4` identities, associativity/distributivity fuzz)

2. `Функциональная корректность pairing`
- prepared vs on-chain equivalence
- single vs multi consistency
- strict path matrix/debug probes

3. `Безопасность новых verifier-контрактов`
- tamper tests
- quorum/expiry/epoch checks
- replay protection (`consume` повторно -> revert)
- merkle proof validity

4. `Gas profiling`
- stage-level benches
- micro benches по ядру арифметики
- архитектурные baseline vs new path

## 8.2. Набор тестовых файлов

- `test/BigIntMNTFinal.t.sol`
- `test/MNT4ExtensionV3Final.t.sol`
- `test/MNT4TatePairingArithmeticV1.t.sol`
- `test/MNT4TatePairingV4.t.sol`
- `test/PairingRelationVerifierR4.t.sol`
- `test/PairingArtifactVerifierR8.t.sol`
- `test/FoldingVerifierR5.t.sol`
- `test/SparsePreparedDebug.t.sol`

---

## 9. Подробный gas-отчет и интерпретация

Источник: `forge test --offline --gas-report` (последний полный прогон, 6 марта 2026).

### 9.1. Главные итоговые цифры (старый compute-path)

#### 9.1.1. Pairing в режиме fixed-Q prepared vs full on-chain

- `testGasBench_pairing_fixedQ_prepared_sparse_only_word`: `258,189,002`
  Это self-path benchmark: включает `prepareFixedQBlobSparse` внутри вызова.
- `testGasBench_prepare_fixedQ_sparse_blob_only`: `194,182,419`

Оценка pairing без отдельной фазы prepare (разностная):

- `258,189,002 - 194,182,419 = 64,006,583` (оценка для prepared compute-only в этой harness-конфигурации).

Full on-chain:

- `testGasBench_pairing_fixedQ_onchain_only_word`: `251,151,360`

Почему значение on-chain здесь близко к prepared-self:

- prepared-self benchmark платит полную цену `prepare` в том же вызове;
- full-onchain не имеет отдельного prepare шага, но платит за генерацию линий в loop.

#### 9.1.2. Тот же baseline через R4-тест

- `testGasBench_r4_baseline_onchain_prepared_single_word`: `87,279,357`
- `testGasBench_r4_baseline_onchain_full_single_word`: `251,404,375`

Отличие этого baseline от `258,189,002`:

- в R4 baseline prepared-blob уже создан в `setUp`, benchmark не включает on-the-fly `prepare` внутри самой функции;
- это ближе к реальному fixed-Q deployment сценарию.

### 9.2. Декомпозиция final exponentiation (prepared path probes)

Из `MNT4TatePairingV4.t.sol`:

- Miller output probe: `238,123,348`
- Inv probe: `241,148,282` -> инверсия: `+3,024,934`
- First chunk probe: `241,263,321` -> first chunk: `+115,039`
- W1 probe: `241,294,048` -> Frobenius-stage: `+30,727`
- W0 probe: `258,049,695` -> hard-part W0: `+16,755,647`
- Final stage probe: `258,237,664` -> финальный mul/finish: `+187,969`

Главный потребитель FE: `W0`-стадия.

### 9.3. Разбор sparse-stage benchmark'ов (line eval / mulByLine)

Использованы тесты:

- `line_eval_zero_round`: `186,757,251`
- `line_eval_one_round`: `186,774,978` -> первый double line-eval: `+17,727`
- `line_eval_only`: `197,948,213`

- `mulByLine_zero_round`: `186,784,857`
- `mulByLine_one_round`: `186,871,227` -> `fq4Sqr + first mulByLine`: `+86,370`
- `mulByLine_only`: `226,970,453`

При `L=376`, `H_eff=124` (включая neg-loop correction) получаются оценки:

- add-line-eval ~ `36.5k` газа/шаг
- extra add mulByLine ~ `62.2k` газа/шаг

Zero-blob контрольные тесты:

- `line_eval_zero_blob_one_round`: `229,850`
- `mulByLine_zero_blob_one_round`: `230,843`
- `mulByLine_zero_blob_zero_round`: `146,289`

Они подтверждают, что основная цена полного stage идет от реальных coeffs/операций, а не от одной только оболочки теста.

### 9.4. Code-shards / EXTCODECOPY

- `testGasBench_pairing_fixedQ_prepared_sparse_code_shards_only_word`: `68,978,164`
- `testGasBench_pairing_fixedQ_prepared_sparse_code_shards_digest_probe`: `69,531,835`

Их нужно сравнивать с prepared benchmark без on-the-fly prepare (не с self-бенчем 258M). В текущем наборе это один из наиболее дешевых compute-path режимов single pairing.

### 9.5. Multi-pairing (2 points)

- `multi_pairing_fixedQ_prepared_sparse_only_word`: `293,625,692`
- `multi_pairing_fixedQ_onchain_only_word`: `286,582,809`
- `multi_pairing_fixedQ_prepared_sparse_code_shards_only_word`: `104,391,670`

Наблюдение:

- shared Miller loop реализован, но в self-бенчах с on-the-fly prepare общая картина искажается ценой генерации blobs;
- для честного масштабирования multi нужно брать fixed-prepared input path (precomputed blobs/shards), а не self-prepare path.

---

## 10. Газ новой архитектуры (R4/R8/R5)

## 10.1. R4 PairingRelationVerifier

- `testGasBench_r4_verify_single_valid`: `58,807`
- `testGasBench_r4_verify_multi2_valid`: `62,243`

Baseline сравнение в том же наборе:

- `baseline prepared single word`: `87,279,357`
- `baseline full onchain single word`: `251,404,375`

Выигрыш:

- относительно prepared baseline: ~`1484x`
- относительно full onchain baseline: ~`4275x`

## 10.2. R8 PairingArtifactVerifier

- `testGasBench_new_r8_verify_single_quorum2`: `94,418`
- `testGasBench_new_r8_verify_multi2_quorum2`: `97,511`
- `testGasBench_new_r8_consume_single_quorum2`: `150,337`

Надбавка к R4 объясняется artifact-binding, quorum signature verification и replay-protected consume-path.

## 10.3. R5 FoldingVerifier

- `testGasBench_new_r5_submit_bundle8_quorum2`: `159,902`
- `testGasBench_new_r5_verify_claim_bundle8`: `37,654`
- `testGasBench_new_r5_consume_claim_bundle8`: `94,625`
- `testGasBench_baseline_r8_verify_single_quorum2`: `50,277` (локальный baseline в этом тесте)

Практический смысл:

- после публикации bundle отдельная верификация claim еще дешевле, чем одиночная R8-проверка;
- это база для масштабирования большого числа pairing-related проверок.

---

## 11. Газ ядра арифметики (microbench)

Важно: эти тесты меряют целые test-functions с циклами, поэтому деление на `N` дает ориентир, а не абсолютный нижний предел одной голой операции.

### 11.1. BigInt (`test/BigIntMNTFinal.t.sol`)

Параметры циклов из тестов:

- `add3_internal`: `N=16384`, gas `5,525,364` -> ~`337`/iter
- `add3_external_stack`: `N=4096`, gas `15,874,067` -> ~`3,875`/iter
- `sub3_external_stack`: `N=4096`, gas `15,505,486` -> ~`3,785`/iter
- `montMul3_internal`: `N=2048`, gas `6,064,053` -> ~`2,961`/iter
- `montSqr3_internal`: `N=2048`, gas `6,040,303` -> ~`2,949`/iter
- `montMul3_external_stack`: `N=512`, gas `3,320,331` -> ~`6,485`/iter
- `montSqr3_external_stack`: `N=512`, gas `3,222,473` -> ~`6,293`/iter
- `inv3_external_stack`: `N=16`, gas `45,614,911` -> ~`2,850,932`/iter
- `inv3Modexp_external_stack`: `N=16`, gas `737,533` -> ~`46,095`/iter

Отдельно видно, что modexp backend на inversion радикально дешевле native inversion в этой конфигурации.

### 11.2. Extension (`test/MNT4ExtensionV3Final.t.sol`)

- `fq2Mul_external_memory_struct`: `N=64`, gas `1,379,806` -> ~`21,559`/iter
- `fq4Mul_external_memory_struct`: `N=16`, gas `978,877` -> ~`61,179`/iter
- `fq2Mul_external_packed`: `N=512`, gas `9,007,846` -> ~`17,593`/iter
- `fq4MulByV_external_packed`: `N=4096`, gas `52,732,660` -> ~`12,874`/iter
- `fq2Inv_external_memory_struct`: `N=8`, gas `21,122,800` -> ~`2,640,350`/iter
- `fq4Inv_external_memory_struct`: `N=4`, gas `10,796,882` -> ~`2,699,220`/iter
- `testBenchFq4Sqr64`: `N=64`, gas `2,375,843` -> ~`37,122`/iter
- `testBenchFq4Mul32`: `N=32`, gas `1,431,332` -> ~`44,729`/iter

---

## 12. Что именно измеряют два «финальных значения pairing» и чем они отличаются

В проекте есть как минимум два типа "финальных" парных чисел:

1. `final pairing compute` на старой архитектуре:
- `tatePairingFixedQPreparedSparse...`
- `tatePairingFixedQOnchain...`

Разница между ними:

- prepared path получает line coefficients из prepared data (off-loop precompute),
- onchain path генерирует линии в loop (`_doublingStep/_mixedAdditionStep`), что значительно дороже.

2. `verification result` на новой архитектуре:
- `PairingRelationVerifier / PairingArtifactVerifier / FoldingVerifier`

Здесь on-chain pairing не вычисляется. Проверяется подпись/доказательство на `statementHash/outputHash/artifactHash/bundleHash`. Поэтому итоговые числа на порядки ниже.

---

## 13. Сравнение подходов и разумные альтернативы для исследования

Ниже список направлений, которые стоит сравнить в диссертационной части как альтернативы текущему baseline.

### 13.1. Базовая арифметика Fp

- Montgomery (текущий)
- Barrett
- Hybrid lazy reduction + редкие canonical reduce
- Native inversion vs modexp inversion vs EEA backend

Что сравнивать:

- gas/op для mul/sqr/add/sub/inv
- влияние на `fq2Mul/fq4Mul` и на full Miller

### 13.2. Уровень Fq2/Fq4

- Karatsuba vs schoolbook для `fq2Mul/fq4Mul`
- tower-aware squaring формулы
- fused primitives (`lineEval+mulByLine`) vs раздельные вызовы

### 13.3. Miller loop data delivery

- memory blob
- calldata blob
- EXTCODECOPY code-shards
- возможная компрессия coeffs и bit-packed digits

### 13.4. Архитектурный уровень

- full compute on-chain
- relation verification (R4)
- artifact-aware verification (R8)
- folded/aggregated verification (R5)

Именно это сравнение и формирует научную часть "почему compute-only подход системно непрактичен и какая архитектура практична".

---

## 14. Идеи из последних работ и что уже применено в проекте

Ниже резюме по материалам, которые использовались в проектной линии (по ранее проведенному обзору):

1. `ePrint 2024/1790` (Tate pairing / subgroup membership revisit)
- ключевая идея для проекта: shared Miller accumulator и reuse общей структуры Miller при batch/мульти проверках;
- это отражено в `multiMiller...` и shared-loop path.

2. `HackMD: emulated pairing`
- ключевая идея: тяжелую арифметику выгодно выносить из on-chain compute в проверяемую off-chain execution/attestation модель;
- это соответствует траектории `R4->R8->R5`.

3. `Sonobe` (folding-oriented stack)
- ключевая идея: агрегация большого количества проверок в компактный верифицируемый объект;
- в проекте эта логика отражена в `FoldingVerifier`.

4. `ePrint 2024/640` (cycle-friendly curves / recursion context)
- полезная для диссертации часть: оценка cycle-friendly конструкций и инженерных trade-off'ов между proving/verifying cost;
- используется как теоретическая опора для перехода от pure on-chain compute к архитектуре с проверкой отношений/артефактов.

5. `ePrint 2023/1192` (pairings over Pasta curves)
- полезный вывод: альтернативные curve/pairing конструкции могут быть оптимизированы под recursion-инфраструктуру, а не только под “прямой on-chain compute pairing”; 
- для диссертации это аргумент в пользу архитектурного сопоставления curve/system design choices.

6. `Ginger-lib / MNT cycle ecosystem`
- полезная часть: зрелые библиотеки обычно ориентированы на off-chain proving pipelines и recursion tooling, а не на прямой on-chain compute pairing в EVM;
- в проекте это подтверждает выбранный сдвиг к verification-first on-chain архитектуре.

---

## 15. Куда развивать работу до уровня полноценной диссертации

### 15.1. Теоретическая часть

Уже есть:

- `LOWER_BOUND_PAIRING_MNT4.tex` (черновой вариант строгой модели).

Нужно довести:

- строгая и однозначная lower-bound модель (implementation-agnostic насколько возможно);
- отдельная формальная теорема по корректности denominator elimination в выбранной постановке divisor/point-at-infinity;
- набор доказуемо корректных оптимизаций (не только эмпирических).

### 15.2. Экспериментальная часть

Нужно зафиксировать reproducible benchmark protocol:

- единая среда (компилятор, optimizer runs, EVM fork);
- таблицы по старой и новой архитектуре;
- амортизационные сценарии (`prepare once`, `many verifies`).

### 15.3. Научная новизна (рабочая формулировка)

Новизна не в "еще одной реализации pairing", а в:

- формальной границе применимости полного on-chain pairing на MNT4-753 в EVM;
- архитектуре перехода от compute к verify с artifact/folding слоями;
- единой методике "матмодель + реализация + газовые доказательства" для cycle-friendly pairing systems.

---

## 16. Приложение A: Полный перечень результатов последнего gas-report

Таблица ниже включает все строки `[PASS]` из последнего полного прогона `forge test --offline --gas-report`, сгруппированные по test file.

| Test File | Test | Gas |
|---|---|---|
| test/PairingArtifactVerifierR8.t.sol | `testGasBench_new_r8_consume_single_quorum2()` | 150337 |
| test/PairingArtifactVerifierR8.t.sol | `testGasBench_new_r8_verify_multi2_quorum2()` | 97511 |
| test/PairingArtifactVerifierR8.t.sol | `testGasBench_new_r8_verify_single_quorum2()` | 94418 |
| test/PairingArtifactVerifierR8.t.sol | `testR8_consumeVerifiedForPoints_replayReverts()` | 215850 |
| test/PairingArtifactVerifierR8.t.sol | `testR8_verifyForPoints_failOnInsufficientQuorum()` | 66641 |
| test/PairingArtifactVerifierR8.t.sol | `testR8_verifyForPoints_revertOnExpiredArtifact()` | 69578 |
| test/PairingArtifactVerifierR8.t.sol | `testR8_verifyForPoints_validSingle()` | 90035 |
| test/FoldingVerifierR5.t.sol | `testGasBench_baseline_r8_verify_single_quorum2()` | 50277 |
| test/FoldingVerifierR5.t.sol | `testGasBench_new_r5_consume_claim_bundle8()` | 94625 |
| test/FoldingVerifierR5.t.sol | `testGasBench_new_r5_submit_bundle8_quorum2()` | 159902 |
| test/FoldingVerifierR5.t.sol | `testGasBench_new_r5_verify_claim_bundle8()` | 37654 |
| test/FoldingVerifierR5.t.sol | `testR5_consumeClaim_replayReverts()` | 379698 |
| test/FoldingVerifierR5.t.sol | `testR5_submitAndVerifyClaim_valid()` | 258212 |
| test/FoldingVerifierR5.t.sol | `testR5_verifyClaim_failOnBadMerkleProof()` | 258133 |
| test/FoldingVerifierR5.t.sol | `testR5_verifyClaim_revertOnExpiredBundle()` | 246280 |
| test/PairingRelationVerifierR4.t.sol | `testGasBench_r4_baseline_onchain_full_single_word()` | 251404375 |
| test/PairingRelationVerifierR4.t.sol | `testGasBench_r4_baseline_onchain_prepared_single_word()` | 87279357 |
| test/PairingRelationVerifierR4.t.sol | `testGasBench_r4_verify_multi2_valid()` | 62243 |
| test/PairingRelationVerifierR4.t.sol | `testGasBench_r4_verify_single_valid()` | 58807 |
| test/PairingRelationVerifierR4.t.sol | `testR4_verifyForPoints_failOnTamperedOutput()` | 54953 |
| test/PairingRelationVerifierR4.t.sol | `testR4_verifyForPoints_failOnTamperedPoints()` | 55901 |
| test/PairingRelationVerifierR4.t.sol | `testR4_verifyForPoints_revertInactiveFixedQ()` | 78877 |
| test/PairingRelationVerifierR4.t.sol | `testR4_verifyForPoints_validSingle()` | 87761411 |
| test/PairingRelationVerifierR4.t.sol | `testR4_verifyStatement_validDirectPath()` | 57274 |
| test/MNT4TatePairingV4.t.sol | `testCodeShards_pairingMulti_EqualsPreparedMem()` | 404739448 |
| test/MNT4TatePairingV4.t.sol | `testCodeShards_pairingSingle_EqualsPreparedMem()` | 333946791 |
| test/MNT4TatePairingV4.t.sol | `testCodeShards_shapes()` | 60762 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_multi_pairing_fixedQ_prepared_sparse_code_shards_digest_probe()` | 104945957 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_multi_pairing_fixedQ_prepared_sparse_code_shards_only_word()` | 104391670 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_code_shards_digest_probe()` | 69531835 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_code_shards_only_word()` | 68978164 |
| test/MNT4TatePairingArithmeticV1.t.sol | `testFq4PowSmallSmoke()` | 29288283 |
| test/MNT4TatePairingArithmeticV1.t.sol | `testG1OpsSmoke()` | 5293987 |
| test/MNT4TatePairingArithmeticV1.t.sol | `testG2OpsSmoke()` | 5461596 |
| test/MNT4TatePairingArithmeticV1.t.sol | `testGasBench_pairingArithmetic()` | 40289733 |
| test/MNT4TatePairingArithmeticV1.t.sol | `testGasReport_internalStyleBenchV2()` | 74370248 |
| test/MNT4TatePairingArithmeticV1.t.sol | `testGasReport_internalStyleBench_pairingOps()` | 90220714 |
| test/MNT4TatePairingArithmeticV1.t.sol | `testMillerAccumulateSmoke()` | 125704 |
| test/SparsePreparedDebug.t.sol | `testLineEvalZeroBlobOneRound()` | 216141 |
| test/SparsePreparedDebug.t.sol | `testMulProbeZeroBlobRetRound0()` | 142597 |
| test/SparsePreparedDebug.t.sol | `testMulProbeZeroBlobRound0()` | 144197 |
| test/SparsePreparedDebug.t.sol | `testMulZeroBlobRound0()` | 142795 |
| test/SparsePreparedDebug.t.sol | `testMulZeroBlobRound1()` | 220456 |
| test/MNT4ExtensionV3Final.t.sol | `testBenchFq4Mul32()` | 1431332 |
| test/MNT4ExtensionV3Final.t.sol | `testBenchFq4Sqr64()` | 2375843 |
| test/MNT4ExtensionV3Final.t.sol | `testFq2Inv_MulOne()` | 2676080 |
| test/MNT4ExtensionV3Final.t.sol | `testFq2Mul_Specific()` | 48224 |
| test/MNT4ExtensionV3Final.t.sol | `testFq2Sqr_MatchesMul()` | 52021 |
| test/MNT4ExtensionV3Final.t.sol | `testFq4Inv_MulOne()` | 2778961 |
| test/MNT4ExtensionV3Final.t.sol | `testFq4MulByV_MatchesGeneralMul()` | 96424 |
| test/MNT4ExtensionV3Final.t.sol | `testFq4Mul_Identity()` | 79577 |
| test/MNT4ExtensionV3Final.t.sol | `testFq4Mul_Specific()` | 109952 |
| test/MNT4ExtensionV3Final.t.sol | `testFq4Sqr_MatchesMul()` | 126935 |
| test/MNT4ExtensionV3Final.t.sol | `testFuzz_Fq2Mul_Associativity(uint64,uint64,uint64,uint64,uint64,uint64)` |  111488 |
| test/MNT4ExtensionV3Final.t.sol | `testFuzz_Fq2Mul_Distributivity(uint64,uint64,uint64,uint64,uint64,uint64)` |  110398 |
| test/MNT4ExtensionV3Final.t.sol | `testFuzz_Fq4Mul_Associativity(uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64,uint64)` |  289486 |
| test/MNT4ExtensionV3Final.t.sol | `testGasBench_fq2Inv_external_memory_struct()` | 21122800 |
| test/MNT4ExtensionV3Final.t.sol | `testGasBench_fq2Mul_external_memory_struct()` | 1379806 |
| test/MNT4ExtensionV3Final.t.sol | `testGasBench_fq2Mul_external_packed()` | 9007846 |
| test/MNT4ExtensionV3Final.t.sol | `testGasBench_fq4Inv_external_memory_struct()` | 10796882 |
| test/MNT4ExtensionV3Final.t.sol | `testGasBench_fq4MulByV_external_packed()` | 52732660 |
| test/MNT4ExtensionV3Final.t.sol | `testGasBench_fq4Mul_external_memory_struct()` | 978877 |
| test/MNT4ExtensionV3Final.t.sol | `testGasReport_internalStyleBench_allOps()` | 195082562 |
| test/MNT4TatePairingV4.t.sol | `testDebug_CopyPoints_DuplicateInputKeepsDuplicate()` | 17066 |
| test/MNT4TatePairingV4.t.sol | `testDebug_FirstRound_DoubleLineMul_Consistency()` | 189011033 |
| test/MNT4TatePairingV4.t.sol | `testDebug_Fq4MulPointer_MatchesReference()` | 131907 |
| test/MNT4TatePairingV4.t.sol | `testDebug_MillerMultiOne_EqualsSingle_InsideHarness()` | 297602891 |
| test/MNT4TatePairingV4.t.sol | `testDebug_MillerMultiOne_Fq4EqBySub_MemoryPath()` | 297603352 |
| test/MNT4TatePairingV4.t.sol | `testDebug_MillerPerPointCoords_AreEqual_WhenDigestsDiffer()` | 298735194 |
| test/MNT4TatePairingV4.t.sol | `testDebug_MillerSingleRepeatSameInput_IsDeterministic()` | 298930479 |
| test/MNT4TatePairingV4.t.sol | `testDebug_MillerTwoCalls_DoNotMutateBlobs()` | 290979960 |
| test/MNT4TatePairingV4.t.sol | `testDebug_OnchainVsPrepared_FirstMismatchProbe()` | 1197999581 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_DuplicateSingleSquareVsMulti_FirstMismatchProbe()` | 887642314 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_FirstMismatchProbe()` | 289992541 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_FirstMismatchVsProductionDigests()` | 587605699 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_MultiDigest_DoesNotMutateBlobs()` | 361817770 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_MultiDigest_DoesNotMutatePoints()` | 361701277 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_MultiDigest_IsDeterministicAcrossCalls()` | 361665696 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_MultiRawDigestTwice_SameContext()` | 360620668 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_MultiRawDigest_IsDeterministicAcrossCalls()` | 368659436 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_SinglesDigest_DoesNotMutateBlobs()` | 361910992 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_SinglesDigest_DoesNotMutatePoints()` | 361793803 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_SinglesProductDigest_IsDeterministicAcrossCalls()` | 361759831 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_SinglesRawDigestTwice_SameContext()` | 360650165 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_SinglesRawDigest_IsDeterministicAcrossCalls()` | 368665658 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_TwoSinglesVsMulti_FirstMismatchProbe()` | 965730086 |
| test/MNT4TatePairingV4.t.sol | `testDebug_SharedLoop_TwoSinglesVsMulti_PathMatrixProbe()` | 1140595472 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_multi_pairing_fixedQ_onchain_digest_probe()` | 287138786 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_multi_pairing_fixedQ_onchain_only_word()` | 286582809 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_multi_pairing_fixedQ_prepared_sparse_digest_probe()` | 294181987 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_multi_pairing_fixedQ_prepared_sparse_only()` | 293626638 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_multi_pairing_fixedQ_prepared_sparse_only_word()` | 293625692 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_onchain_digest_probe()` | 251704239 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_onchain_only_word()` | 251151360 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_digest_probe()` | 258743647 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_final_stage_probe()` | 258237664 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_first_chunk_probe()` | 241263321 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_inv_probe()` | 241148282 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_inv_probe_copied()` | 241174515 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_inv_ptr_probe()` | 244098459 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_miller_output_probe()` | 238123348 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_only()` | 258189354 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_only_word()` | 258189002 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_probe()` | 238139260 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_probe_with_final()` | 258238549 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_w0_probe()` | 258049695 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_pairing_fixedQ_prepared_sparse_w1_probe()` | 241294048 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_prepare_fixedQ_sparse_blob_only()` | 194182419 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_arena_probe()` | 7256 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_line_eval_one_round()` | 186774978 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_line_eval_only()` | 197948213 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_line_eval_word_one_round()` | 186776124 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_line_eval_zero_blob_one_round()` | 229850 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_line_eval_zero_round()` | 186757251 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_load_only()` | 186853411 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_loop_len_probe()` | 7881 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_memory_probe()` | 186664380 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_memory_probe_discard()` | 186662506 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_mulByLine_after_prepare_zero_blob_word()` | 192272789 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_mulByLine_one_round()` | 186871227 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_mulByLine_only()` | 226970453 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_mulByLine_word_zero_round()` | 186785627 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_mulByLine_zero_blob_one_round()` | 230843 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_mulByLine_zero_blob_zero_round()` | 146289 |
| test/MNT4TatePairingV4.t.sol | `testGasBench_sparse_stage_mulByLine_zero_round()` | 186784857 |
| test/MNT4TatePairingV4.t.sol | `testOnchainFixedQStrict_FinalMultiOne_EqualsSingle()` | 503717084 |
| test/MNT4TatePairingV4.t.sol | `testOnchainFixedQStrict_FinalMulti_EqualsProductSingles()` | 574596549 |
| test/MNT4TatePairingV4.t.sol | `testOnchainFixedQStrict_MillerMultiOne_EqualsSingle()` | 463800859 |
| test/MNT4TatePairingV4.t.sol | `testOnchainFixedQStrict_MillerMulti_EqualsProductSingles()` | 534671193 |
| test/MNT4TatePairingV4.t.sol | `testOnchainFixedQStrict_MillerSingle_EqualsPreparedSparseSingle()` | 478801532 |
| test/MNT4TatePairingV4.t.sol | `testOnchainFixedQ_EqualsPreparedSparse_Single()` | 516298312 |
| test/MNT4TatePairingV4.t.sol | `testPrepareFixedQBlobSparse_shapes()` | 194182696 |
| test/MNT4TatePairingV4.t.sol | `testPreparedSparseMultiOne_EqualsSingle()` | 333437995 |
| test/MNT4TatePairingV4.t.sol | `testPreparedSparseMulti_EqualsProductOfSingles()` | 404222856 |
| test/MNT4TatePairingV4.t.sol | `testPreparedSparseStrict_FinalMultiOne_EqualsSingle_SameBlobs()` | 334036273 |
| test/MNT4TatePairingV4.t.sol | `testPreparedSparseStrict_FinalMulti_EqualsProductSingles_SameBlobs()` | 404816053 |
| test/MNT4TatePairingV4.t.sol | `testPreparedSparseStrict_MillerMultiOne_EqualsSingle_SameBlobs()` | 298934084 |
| test/MNT4TatePairingV4.t.sol | `testPreparedSparseStrict_MillerMulti_EqualsProductSingles_SameBlobs()` | 369768570 |
| test/MNT4TatePairingV4.t.sol | `testPreparedSparse_EqualsFixedQGenerator()` | 333026752 |
| test/BigIntMNTFinal.t.sol | `testAddCarry()` | 9174 |
| test/BigIntMNTFinal.t.sol | `testAddLargeNoWrap()` | 10426 |
| test/BigIntMNTFinal.t.sol | `testAddSimple()` | 9933 |
| test/BigIntMNTFinal.t.sol | `testAddWrapModP()` | 9979 |
| test/BigIntMNTFinal.t.sol | `testGasBench_add3_external_stack()` | 15874067 |
| test/BigIntMNTFinal.t.sol | `testGasBench_add3_internal()` | 5525364 |
| test/BigIntMNTFinal.t.sol | `testGasBench_add_external_memory_array()` | 1553909 |
| test/BigIntMNTFinal.t.sol | `testGasBench_fromMontgomery3_external_stack()` | 1474000 |
| test/BigIntMNTFinal.t.sol | `testGasBench_inv3Modexp_external_stack()` | 737533 |
| test/BigIntMNTFinal.t.sol | `testGasBench_inv3_external_stack()` | 45614911 |
| test/BigIntMNTFinal.t.sol | `testGasBench_montMul3_external_stack()` | 3320331 |
| test/BigIntMNTFinal.t.sol | `testGasBench_montMul3_internal()` | 6064053 |
| test/BigIntMNTFinal.t.sol | `testGasBench_montSqr3_external_stack()` | 3222473 |
| test/BigIntMNTFinal.t.sol | `testGasBench_montSqr3_internal()` | 6040303 |
| test/BigIntMNTFinal.t.sol | `testGasBench_sub3_external_stack()` | 15505486 |
| test/BigIntMNTFinal.t.sol | `testGasBench_toMontgomery3_external_stack()` | 1739743 |
| test/BigIntMNTFinal.t.sol | `testGasReport_internalStyleBench_allOps()` | 108563894 |
| test/BigIntMNTFinal.t.sol | `testInvModexpMulOne()` | 76292 |
| test/BigIntMNTFinal.t.sol | `testInvMulOne()` | 2870573 |
| test/BigIntMNTFinal.t.sol | `testInvNativeEqualsModexp()` | 2901240 |
| test/BigIntMNTFinal.t.sol | `testMontMulNegOneSquare()` | 28093 |
| test/BigIntMNTFinal.t.sol | `testMontMulOne()` | 27242 |
| test/BigIntMNTFinal.t.sol | `testMontMulSmall()` | 36317 |
| test/BigIntMNTFinal.t.sol | `testMontSqrMatchesMul()` | 28352 |
| test/BigIntMNTFinal.t.sol | `testMontgomeryRoundtripLarge()` | 19076 |
| test/BigIntMNTFinal.t.sol | `testMontgomeryRoundtripSmall()` | 18848 |
| test/BigIntMNTFinal.t.sol | `testMulBy13MatchesRepeatedAdd()` | 10309 |
| test/BigIntMNTFinal.t.sol | `testSubSimple()` | 9238 |
| test/BigIntMNTFinal.t.sol | `testSubUnderflow()` | 9502 |

---

## 17. Приложение B: Комментарии по интерпретации gas-report

- Значения `gas` в forge-отчете измеряют стоимость выполнения конкретной test-функции целиком.
- Для тестов с циклами корректно делить на `N` только как ориентир upper-level `gas/iter` в рамках этой harness.
- Для строгого per-op учета нужно либо:
  - использовать dedicated internal bench contracts с минимальным wrapper overhead,
  - либо вычислять разности между `one_round/zero_round/full_round` probes (что и сделано для ключевых stage-оценок Miller/FE).


## 18. Каталог benchmark-тестов: что измеряет каждый

Ниже расшифровка всех benchmark-имен из последнего gas-report.

### 18.1. `test/MNT4TatePairingV4.t.sol`

| Benchmark | Что измеряет |
|---|---|
| `testGasBench_prepare_fixedQ_sparse_blob_only()` | Только генерация prepared sparse blobs (`dblSparse/addSparse`) для fixed-Q. |
| `testGasBench_pairing_fixedQ_prepared_sparse_only()` | Full prepared pairing в self-path (включая prepare внутри benchmark-вызова). |
| `testGasBench_pairing_fixedQ_prepared_sparse_only_word()` | То же, но возврат только первого word результата для минимизации post-processing. |
| `testGasBench_multi_pairing_fixedQ_prepared_sparse_only()` | Multi prepared pairing (2 точки) в self-path, включая prepare. |
| `testGasBench_multi_pairing_fixedQ_prepared_sparse_only_word()` | То же для multi, word-only результат. |
| `testGasBench_pairing_fixedQ_onchain_only_word()` | Full on-chain pairing (генерация линий on-chain), word-only вывод. |
| `testGasBench_multi_pairing_fixedQ_onchain_only_word()` | Multi full on-chain pairing (2 точки), word-only вывод. |
| `testGasBench_pairing_fixedQ_onchain_digest_probe()` | Full on-chain pairing + digest-path output. |
| `testGasBench_multi_pairing_fixedQ_onchain_digest_probe()` | Multi full on-chain pairing + digest-path output. |
| `testGasBench_pairing_fixedQ_prepared_sparse_probe()` | Stage probe prepared-path без FE finish (контроль стадий/arena). |
| `testGasBench_pairing_fixedQ_prepared_sparse_probe_with_final()` | Stage probe prepared-path c FE finish. |
| `testGasBench_pairing_fixedQ_prepared_sparse_final_stage_probe()` | Probe для финальной стадии FE в prepared path. |
| `testGasBench_pairing_fixedQ_prepared_sparse_miller_output_probe()` | Стоимость получения Miller output до FE. |
| `testGasBench_pairing_fixedQ_prepared_sparse_inv_probe()` | Стоимость до/после inversion в FE (первая FE подстадия). |
| `testGasBench_pairing_fixedQ_prepared_sparse_inv_probe_copied()` | Inversion probe c дополнительным copy-path. |
| `testGasBench_pairing_fixedQ_prepared_sparse_inv_ptr_probe()` | Pointer-level inversion probe (включая den ptr диагностику). |
| `testGasBench_pairing_fixedQ_prepared_sparse_first_chunk_probe()` | FE first-chunk стадия (после inversion). |
| `testGasBench_pairing_fixedQ_prepared_sparse_w1_probe()` | FE Frobenius/W1 стадия. |
| `testGasBench_pairing_fixedQ_prepared_sparse_w0_probe()` | FE hard-part W0 chain стадия (главный FE cost). |
| `testGasBench_pairing_fixedQ_prepared_sparse_digest_probe()` | Full prepared pairing + digest-path output. |
| `testGasBench_multi_pairing_fixedQ_prepared_sparse_digest_probe()` | Multi prepared pairing + digest-path output. |
| `testGasBench_sparse_stage_arena_probe()` | Размер arena/words для sparse prepared path. |
| `testGasBench_sparse_stage_loop_len_probe()` | Loop length (длина `ATE_LOOP_ENC`) probe. |
| `testGasBench_sparse_stage_load_only()` | Только загрузка sparse coeffs без line-eval/mul-by-line. |
| `testGasBench_sparse_stage_line_eval_only()` | Только line evaluation на полном количестве раундов. |
| `testGasBench_sparse_stage_mulByLine_only()` | Только mulByLine стадия на полном количестве раундов. |
| `testGasBench_sparse_stage_line_eval_one_round()` | Line evaluation ровно одного раунда (double step baseline). |
| `testGasBench_sparse_stage_mulByLine_one_round()` | MulByLine ровно одного раунда. |
| `testGasBench_sparse_stage_line_eval_zero_round()` | Line evaluation с нулем раундов (baseline overhead). |
| `testGasBench_sparse_stage_mulByLine_zero_round()` | MulByLine с нулем раундов (baseline overhead). |
| `testGasBench_sparse_stage_line_eval_zero_blob_one_round()` | One-round line evaluation по zero-blob coeffs. |
| `testGasBench_sparse_stage_mulByLine_zero_blob_one_round()` | One-round mulByLine по zero-blob coeffs. |
| `testGasBench_sparse_stage_mulByLine_zero_blob_zero_round()` | Zero-round mulByLine по zero-blob coeffs (чистый baseline). |
| `testGasBench_sparse_stage_memory_probe()` | Probe memory layout/ptr после подготовки dbl+add blobs. |
| `testGasBench_sparse_stage_line_eval_word_one_round()` | One-round line-eval, word-only output. |
| `testGasBench_sparse_stage_mulByLine_word_zero_round()` | Zero-round mulByLine, word-only output. |
| `testGasBench_sparse_stage_memory_probe_discard()` | Memory probe для сценария только dbl blob (без add path). |
| `testGasBench_sparse_stage_mulByLine_after_prepare_zero_blob_word()` | MulByLine на zero-blob после отдельного prepare (изоляция влияния memory growth). |
| `testGasBench_pairing_fixedQ_prepared_sparse_code_shards_only_word()` | Prepared pairing c загрузкой coeffs через code-shards/EXTCODECOPY, word-only. |
| `testGasBench_multi_pairing_fixedQ_prepared_sparse_code_shards_only_word()` | Multi prepared pairing c code-shards, word-only. |
| `testGasBench_pairing_fixedQ_prepared_sparse_code_shards_digest_probe()` | Prepared pairing c code-shards + digest output. |
| `testGasBench_multi_pairing_fixedQ_prepared_sparse_code_shards_digest_probe()` | Multi prepared pairing c code-shards + digest output. |

### 18.2. `test/BigIntMNTFinal.t.sol`

| Benchmark | Что измеряет |
|---|---|
| `testGasBench_add3_internal()` | Циклический benchmark внутреннего `BigIntMNT.add3` (stack-only path). |
| `testGasBench_add3_external_stack()` | Циклический benchmark `add3` через external stack ABI harness. |
| `testGasBench_add_external_memory_array()` | Циклический benchmark `add` через memory-array ABI (`uint256[3]`). |
| `testGasBench_montMul3_internal()` | Циклический benchmark внутреннего `montMul3` на full-width входах. |
| `testGasBench_montSqr3_internal()` | Циклический benchmark внутреннего `montSqr3` на full-width входах. |
| `testGasBench_sub3_external_stack()` | Циклический benchmark `sub3` через external stack ABI harness. |
| `testGasBench_montMul3_external_stack()` | Циклический benchmark `montMul3` через external stack ABI harness. |
| `testGasBench_montSqr3_external_stack()` | Циклический benchmark `montSqr3` через external stack ABI harness. |
| `testGasBench_toMontgomery3_external_stack()` | Циклический benchmark перевода в Montgomery через external stack ABI. |
| `testGasBench_fromMontgomery3_external_stack()` | Циклический benchmark перевода из Montgomery через external stack ABI. |
| `testGasBench_inv3_external_stack()` | Циклический benchmark `inv3` (native backend path в текущей конфигурации). |
| `testGasBench_inv3Modexp_external_stack()` | Циклический benchmark `inv3Modexp` (precompile-based inversion). |
| `testGasReport_internalStyleBench_allOps()` | Сводный benchmark-контракт, прогоняющий весь набор BigInt операций. |

### 18.3. `test/MNT4ExtensionV3Final.t.sol`

| Benchmark | Что измеряет |
|---|---|
| `testBenchFq4Sqr64()` | Внутренний bench: 64 итерации `fq4Sqr` в harness. |
| `testBenchFq4Mul32()` | Внутренний bench: 32 итерации `fq4Mul` в harness. |
| `testGasBench_fq2Mul_external_memory_struct()` | Циклический `fq2Mul` через struct memory ABI. |
| `testGasBench_fq4Mul_external_memory_struct()` | Циклический `fq4Mul` через struct memory ABI. |
| `testGasBench_fq2Mul_external_packed()` | Циклический `fq2Mul` через packed (6-word) ABI path. |
| `testGasBench_fq4MulByV_external_packed()` | Циклический `fq4MulByV` через packed (12-word) ABI path. |
| `testGasBench_fq2Inv_external_memory_struct()` | Циклический `fq2Inv` через struct memory ABI. |
| `testGasBench_fq4Inv_external_memory_struct()` | Циклический `fq4Inv` через struct memory ABI. |
| `testGasReport_internalStyleBench_allOps()` | Сводный benchmark-контракт по ключевым Fq2/Fq4 операциям. |

### 18.4. `test/MNT4TatePairingArithmeticV1.t.sol`

| Benchmark | Что измеряет |
|---|---|
| `testGasBench_pairingArithmetic()` | Композитный benchmark reference arithmetic path (G1/G2 ops + millerAcc + pow). |
| `testGasReport_internalStyleBenchV2()` | Сводный bench V2 (millerAcc loop, fq4Pow variants, empty loop baseline). |
| `testGasReport_internalStyleBench_pairingOps()` | Сводный bench pairing ops (G1/G2 affine ops, millerAccumulate, pow variants). |

### 18.5. `test/PairingRelationVerifierR4.t.sol`

| Benchmark | Что измеряет |
|---|---|
| `testGasBench_r4_verify_single_valid()` | Новая архитектура R4: verify одного statement/output с одной точкой. |
| `testGasBench_r4_verify_multi2_valid()` | R4 verify для двух точек (`pairs=2`). |
| `testGasBench_r4_baseline_onchain_prepared_single_word()` | Baseline старой архитектуры: prepared on-chain pairing (word output). |
| `testGasBench_r4_baseline_onchain_full_single_word()` | Baseline старой архитектуры: full on-chain pairing (word output). |

### 18.6. `test/PairingArtifactVerifierR8.t.sol`

| Benchmark | Что измеряет |
|---|---|
| `testGasBench_new_r8_verify_single_quorum2()` | R8 verify single (artifact + quorum=2 signatures). |
| `testGasBench_new_r8_verify_multi2_quorum2()` | R8 verify multi2 (artifact + quorum=2 signatures). |
| `testGasBench_new_r8_consume_single_quorum2()` | R8 consume path (verify + replay-protected consume). |

### 18.7. `test/FoldingVerifierR5.t.sol`

| Benchmark | Что измеряет |
|---|---|
| `testGasBench_new_r5_submit_bundle8_quorum2()` | R5: отправка aggregate bundle (8 claims) + quorum подписи. |
| `testGasBench_new_r5_verify_claim_bundle8()` | R5: проверка одного claim из уже принятого bundle (Merkle verify path). |
| `testGasBench_new_r5_consume_claim_bundle8()` | R5: consume одного claim (Merkle verify + replay protection). |
| `testGasBench_baseline_r8_verify_single_quorum2()` | Baseline внутри R5 suite: проверка одиночного claim через R8 path. |

