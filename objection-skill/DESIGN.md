# objection — дизайн и ресёрч

Цель: усиленный скилл критического мышления для Claude Code — не «чек-лист фреймворков», а рабочая
система из 5 аспектов под единым законом:

> **Сомнение/усилие легально, только если оно направлено на проверяемое,
> пропорционально ставке, и умеет закончиться.**
> (иначе — либо доверчивость, либо зацикленное прожигание токенов сомнением)

Чинит типовые слабые места скиллов этого класса: призыв «проверь допущения» без принуждения к
проверке; вывод и обоснование одним потоком → самоподтверждение; опора на связность текста вместо
пере-вывода из источника (coherence trap); декоративное перечисление названий техник.

---

## Ключевой научный вывод (рамка для всего)

Внутренняя самокоррекция БЕЗ внешнего сигнала ненадёжна и часто ухудшает результат.
Модель может починить ошибку, если ей указать её место, но сама найти это место не может.
Прирост даёт только внешний якорь: инструмент, исполнение, независимый грейдер.
→ Усиление должно быть структурной процедурой, а не «подумай ещё раз».

- Huang et al., ICLR 2024 «LLMs Cannot Self-Correct Reasoning Yet» — https://arxiv.org/abs/2310.01798
- Kamoi et al., TACL 2024 (обзор) — https://github.com/ryokamoi/llm-self-correction-papers

---

## Аспект 1 — Verification Pass (проверка своих выводов, CoVe)

**Механизм:** Chain-of-Verification, факторизованный вариант — на проверочные вопросы
отвечать в ОТДЕЛЬНОМ проходе, НЕ видя исходный ответ, чтобы модель не повторяла свою же ошибку.
Независимые проверочные ответы точнее исходного длинного ответа.

- CoVe — https://arxiv.org/pdf/2309.11495 · https://learnprompting.org/docs/advanced/self_criticism/chain_of_verification
- Devil's Advocate — https://arxiv.org/html/2405.16334v2
- Reflexion — https://arxiv.org/pdf/2303.11366
- Self-Consistency & Reflection — https://handsonai.info/agentic-building-blocks/prompts/prompt-engineering/self-consistency-and-reflection/

---

## Аспект 2 — Граница паранои (сколько проверять, чтобы не зациклиться)

Слепая паранойя измеримо вредит:
- До **95% самопроверок** не дают коррекций (можно подавить без потери точности).
- Самокритика чаще ломает: сдвиги правильно→неправильно ≈0.45 vs неправильно→правильно ≈0.15.
- FlipFlop: «ты уверен?» → модель переобувает верный ответ.
- Overthinking: длинное рассуждение бросает уже правильные ответы; отдача уходит в минус.
- Руминация: модель заново «пережёвывает» уже осмотренное допущение — круг без нового внешнего сигнала ответ не двигает. Умеренно полезна как самопроверка, избыточная — вредит.
- Самопроверка полезна только когда исходная точность НИЗКА → включать по триггеру, не по умолчанию.

- When More Thinking Hurts — https://arxiv.org/abs/2604.10739
- Inverse Scaling in Test-Time Compute — https://arxiv.org/pdf/2507.14417
- Stop Overthinking (survey) — https://github.com/Eclipsess/Awesome-Efficient-Reasoning-LLMs
- Self-Verification Dilemma (95% no-op) — https://arxiv.org/html/2602.03485
- Self-Critique Paradox — https://snorkel.ai/blog/the-self-critique-paradox-why-ai-verification-fails-where-its-needed-most/
- Are You Sure? / FlipFlop — https://arxiv.org/pdf/2311.08596
- DeepSeek-R1 Thoughtology (руминация как «жвачка») — https://arxiv.org/pdf/2504.07128
- Answer Convergence (стоп, когда ответ перестал двигаться) — https://arxiv.org/pdf/2506.02536

---

## Аспект 3 — Skepticism Gate (недоверие ко ВХОДАМ)

Скептицизм направлен на внешние входы (ввод юзера, документы, выводы инструментов, другие агенты).
Два провала: сикофантия (over-trust) и слепой цинизм (blanket skepticism).
⚠️ Главное: скептицизм по умолчанию **коллапсирует там, где нужнее всего** — сфабрикованное
утверждение «в регистре солидного текста» проходит без проверки. Триггер должен быть по
**проверяемости/provenance, а не по тону**.

- Sycophancy: Causes & Mitigations — https://arxiv.org/html/2411.15287v1
- Trust, but Don't Verify (epistemic blind spots) — https://arxiv.org/html/2606.05403
- Sycophancy AND Skepticism in Causal Judgment — https://arxiv.org/abs/2601.08258v3
- Confidence Dichotomy in Tool-Use Agents — https://arxiv.org/pdf/2601.07264
- Epistemic Integrity — https://arxiv.org/pdf/2411.06528

---

## Аспект 4 — Effort Triage (эффективность: сколько думать)

Right-sizing: глубина ∝ (сложность × ставка × неуверенность). Зеркало overthinking — **underthinking**:
модель преждевременно бросает перспективную линию и скачет между поверхностными мыслями
(у неверных ответов БОЛЬШЕ переключений). Лечится «додумай линию до конца, прежде чем менять».

- Underthinking of o1-like LLMs — https://arxiv.org/abs/2501.18585
- SmartSwitch — https://arxiv.org/pdf/2510.19767
- CODA (−60% токенов на лёгком) — https://arxiv.org/pdf/2603.08659
- DiffAdapt — https://arxiv.org/pdf/2510.19669
- Conformal Thinking (стоп по маргинальной отдаче) — https://arxiv.org/html/2602.03814
- Reasoning on a Budget (survey) — https://arxiv.org/html/2507.02076v1

---

## Аспект 5 — Dialogue Gate (доверие юзеру: спросить / действовать / подтвердить)

Решение по VOI = цена неверного допущения − цена прерывания юзера.
Under-ask (дефолт SOTA) → тихие провалы; over-ask → трение/усталость. Один вопрос вовремя
снижал ошибку на 27%. Разделение доверия: юзер — источник истины по ЦЕЛЯМ/приоритетам/разрешениям
(доверяй, спрашивай); проверяемые факты юзера = user-asserted (заземляй). Сырой self-confidence
miscalibrated (90%≈75%) → гейти по проверяемость×ставка×обратимость.

- Value of Information (human-agent) — https://arxiv.org/pdf/2601.06407
- Ask or Assume? — https://arxiv.org/html/2603.26233
- Asking the Right Question at the Right Time — https://arxiv.org/pdf/2402.06509
- Human-in-the-Loop Escalation Design — https://www.digitalapplied.com/blog/human-in-the-loop-escalation-design-ai-agents-2026
- Confidence-gated escalation middleware — https://github.com/ashutoshrana/confidence-escalation

---

## Порядок исполнения в скилле

**0. Effort Triage** (сколько думать) → **1. Skepticism Gate** (входы) →
**2. Paranoia Gate** (свои выводы) → **3. Verification Pass / CoVe** (механизм)
· **⟂ Dialogue Gate** (кросс-режущий, в точках решения/действия).

Effort Triage управляет и самим скиллом: на L0 гейты не запускаются (иначе стек сам станет overthinking).
