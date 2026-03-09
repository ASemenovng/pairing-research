# Итоговый план диссертационной работы: onchain/offchain архитектура для ATE pairing на MNT4-753

## Уточнение по fixed-Q

В этой работе `fixed-Q` означает: для pairing `e(P, Q)` точка `Q` в `G2` рассматривается как константа для конкретного verifier-контекста (например, часть verification key), и поэтому допускается отдельный precompute по `Q`.


Возможны два  варианта fixed-Q:

### A) `Q` как onchain-константа (hardcoded VK)

1. В Ethereum-практике zkSNARK verifier-контракты фиксируют часть `G2`-точек в коде и проверяют pairing-equation.
2. Это видно в:
   1. [EIP-197](https://eips.ethereum.org/EIPS/eip-197): pairing precompile проверяет уравнение pairing; типичный verifier формирует это уравнение из proof + констант VK.
   2. Шаблоне Solidity verifier в `snarkjs`, где `beta/gamma/delta` и др. элементы VK зашиваются как `constant` в контракт и используются при pairing-check: [verifier_groth16.sol.ejs](https://raw.githubusercontent.com/iden3/snarkjs/master/templates/verifier_groth16.sol.ejs), генерация: [snarkjs README](https://raw.githubusercontent.com/iden3/snarkjs/master/README.md).
   3. Генераторе Solidity verifier в `gnark`, где VK-точки также материализуются как константы контракта: [gnark/backend/groth16/bn254/solidity.go](https://raw.githubusercontent.com/Consensys/gnark/master/backend/groth16/bn254/solidity.go).
3. Теоретически это корректно, потому что проверяемое утверждение формулируется относительно фиксированного VK; значит `Q` является частью публичных параметров системы и не “плавает” между вызовами.

### B) `Q`/coeffs приходят offchain, но onchain связаны через commitment/proof

1. Корректная схема для недоверенных offchain-данных: контракт хранит (или получает из доверенного реестра) commitment к параметрам, а во входе получает данные + proof соответствия commitment.
2. Канонический аналог такого паттерна в Ethereum: [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844), где precompile проверяет KZG-proof и отдельно проверяет соответствие commitment ↔ versioned hash (то есть “данные из вне” принимаются только при криптографической привязке к commitment).
3. В нашей архитектуре это реализуется так же по идее:
   1. registry хранит commitment для fixed-Q: [FixedQRegistry.sol](./src/FixedQRegistry.sol);
   2. verifier требует совпадения `fixedQCommitment` со значением из registry и проверяет proof/witness-пакет: [PairingArtifactVerifier.sol](./src/PairingArtifactVerifier.sol).
4. Для полной trustless-модели proof должен доказывать корректность именно pairing-trace (Miller + final exp).

### Почему fixed-Q полезен

1. В pairing-системах precompute по `G2` — стандартный прием:
   1. `arkworks` формирует `G2Prepared` (double/add coefficients) для Miller loop: [arkworks mnt4 g2.rs](https://raw.githubusercontent.com/arkworks-rs/algebra/master/ec/src/models/mnt4/g2.rs).
   2. `arkworks Groth16` использует `prepare_verifying_key` и prepared G2-элементы в верификации: [arkworks groth16 verifier.rs](https://raw.githubusercontent.com/arkworks-rs/groth16/master/src/verifier.rs).
   3. `bellman` аналогично использует `prepare_verifying_key`: [bellman verifier.rs](https://raw.githubusercontent.com/zkcrypto/bellman/main/groth16/src/verifier.rs).
2. Экономический смысл: дорогие операции генерации/подготовки по `Q` амортизируются, onchain остается более компактная проверка.

### Вывод

1. Подход `fixed-Q` корректен, если выполняется инвариант “одна и та же `Q` (или ее commitment) используется на всех этапах: precompute, proof generation, onchain verify”.
2. Следовательно, допустимы две формы:
   1. `Q` зашита в verifier/VK (hardcoded constant model).
   2. `Q` не зашита, но onchain проверяется commitment/proof-связь (committed-parameter model).
3. Некорректна только несвязанная подмена `Q` между offchain и onchain.

---

## Этап 0. Цель, критерии, формализация постановки

1. Зафиксировать 2 целевых режима:
   1. Полный on-chain ATE pairing на MNT4-753 (baseline и исследовательский предел).
   2. Off-chain precompute + on-chain verification (практический режим).
2. Зафиксировать KPI:
   1. Газ single/two-pairing check.
   2. Calldata size.
   3. Off-chain time/memory.
3. Зафиксировать модель угроз:
   1. Контракт не доверяет precompute cache.
   2. Доверенные публичные входы: `P`, `Q`, claimed pairing result (и публичные параметры схемы).

Результат: раздел “Problem statement + success metrics”.

## Этап 1. Теоретический фундамент

1. Теоретическое введение: MNT4/MNT6 cycle, Tate/ATE pairing, структура Miller + final exp.
2. Формальное доказательство корректности оптимизации в `f(O)`.
3. Формальная lower-bound модель стоимости полного on-chain вычисления:
   1. Алгебраический слой (число операций по полям).
   2. Редукция до `Fp`.
   3. Проекция в EVM-cost.
   4. Нижняя оценка, независимая от конкретного кода в пределах явно заданного класса реализаций.
4. Сравнение математических моделей с эмпирическими газ-бенчами (валидация модели).

Результат: полноценная теоретическая глава с леммами/теоремами и верифицируемыми предпосылками.

## Этап 2. Исследование пространства реализаций арифметики

1. Системный разбор вариантов:
   1. Montgomery vs Barrett reduction.
   2. CIOS/FIOS strategies.
   3. Lazy reduction vs eager reduction.
   4. Affine vs Jacobian/mixed для G2-шагов.
2. Для каждого варианта:
   1. Формальная стоимость (в модели операций).
   2. Практический gas microbench.
3. Обоснование окончательного выбора дизайна для full on-chain baseline.

Результат: глава с таблицей альтернатив и аргументированным выбором.

## Этап 3. Завершенный baseline: полный on-chain

1. Финализация двух on-chain веток:
   1. `full onchain` (line generation on-chain).
   2. `prepared/fixed-Q` (streamed coeffs).
2. Единый набор тестов:
   1. Корректность относительно reference реализации.
   2. Differential tests между режимами.
   3. Инварианты pointer/scratch path.
3. Единый набор газ-бенчей по этапам:
   1. Miller.
   2. Final exponentiation (включая W0/W1 probes).
   3. End-to-end pairing.

Результат: полностью воспроизводимый baseline и обоснование практической неприменимости on-chain режима в mainnet.

## Этап 4. Экспериментальная ветка “VM acceleration” (fork VM) - опционально

1. Отдельный эксперимент:
   1. Моделирование новых opcodes/precompiles для big-field arithmetic (по аналогии с EVM384-подходом).
2. Прогон тех же pairing-бенчей в моделируемой VM.
3. Сравнение:
   1. Standard EVM vs Accelerated VM.
   2. Текущий baseline vs published estimates (EVM384-like модели).

Результат: формальное обоснование, какие VM-примитивы дают максимальный выигрыш.

## Этап 5. Новая архитектура: off-chain heavy compute, on-chain compact verification

1. Формализовать объект “pairing computation trace”:
   1. trace” Miller шагов (state transition).
   2. trace” final exponentiation (fixed-chain transitions).
2. Off-chain вычислять:
   1. Все линии.
   2. Все промежуточные состояния.
   3. Предвычисления FE.
3. On-chain проверять корректность relation/proof:
   1. Boundary constraints.
   2. Transition constraints.
   3. Связь с публичными `P, Q, pairing`.
4. Антифрод-модель:
   1. Контракт не доверяет кэшу.
   2. Доверяет только доказательству корректности relation.
   3. Неверный cache отвергается.

Результат: архитектурный переход от compute к verify для ATE pairing.

## Этап 6. Контрактный и off-chain стек

1. Контракты verification-слоя:
   1. `PairingRelationVerifier` (проверка ограничений).
   2. Адаптеры форматов witness/commitments.
2. Off-chain pipeline:
   1. Генерация trace/witness.
   2. Коммитменты к данным.
   3. Генерация succinct proof (или иной компактной доказательной формы).
3. Тесты:
   1. Positive/negative fraud cases.
   2. Fuzz на поврежденные witness blocks.
   3. Совместимость с baseline inputs.
4. Газ-бенчи новой архитектуры:
   1. Verify cost.
   2. Calldata cost.
   3. Total cost на 1/2/N pairing checks.

Результат: практическая реализация нового режима.

## Этап 7. Агрегация и folding

1. Добавить folding/aggregation слой для batch verify.
2. Цель:
   1. Амортизировать on-chain verify cost на много pairing-проверок.
3. Проверить интеграцию с Sonobe-style идеями (агрегация доказательств).
4. Бенчи:
   1. Cost per check при росте batch.
   2. Размер доказательства vs газ.

Результат: масштабируемая версия новой архитектуры.

## Этап 8. Вторая теоретическая часть для новой архитектуры

1. Формальная lower-bound и upper-bound модель для verify-first режима.
2. Теорема корректности relation verifier:
   1. Completeness.
   2. Soundness.
3. Теорема/оценка про антифрод:
   1. Почему подделка precompute без нарушения relation невозможна.
4. Сведение модели к газу (после формальной части).

Результат: строгая теоретическая база для новой архитектуры.

## Этап 9. Сравнение с существующими решениями

1. Сравнить с последними работами:
   1. ePrint 2024/1790 (shared Miller/use-cases Tate).
   2. ePrint 2024/640.
   3. ePrint 2023/1192.
   4. Emulated pairing (HackMD).
   5. Sonobe / folding ecosystem.
   6. Ginger-lib / MNT cycle ecosystem.
   7. Решения на других кривых
2. Таблицы сравнения:
   1. Что считается on-chain.
   2. Что precompute.
   3. Как обеспечивается soundness.
   4. Газ/размер данных/latency.

Результат: завершенный раздел научного вклада.

## Этап 10. Финальные артефакты диссертации

1. Полный код (baseline + new architecture).
2. Реплицируемые скрипты бенчмарков.
3. Теоретические документы (LaTeX).
4. Итоговый технический отчет с таблицами, графиками и анализом trade-offs.

## Формулировка итоговой цели работы

Разработать и теоретически обосновать практическую архитектуру верификации ATE pairing на MNT4-753, где тяжелая арифметика выполняется off-chain, а on-chain выполняется компактная криптографически строгая проверка корректности вычислений, с формальными lower-bound оценками для полного on-chain варианта и доказанной soundness новой модели.
