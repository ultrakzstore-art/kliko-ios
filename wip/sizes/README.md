# Размеры по шаблону и одежда/обувь — незаконченная работа (14.10.2026)

Остановлено на недельном лимите. НЕ компилируется сборкой (папка wip/ вне Sources).
- `sizes-wip.patch` — правки существующих файлов (PostingDims*, PostingModel, PostingSchema, PostingSteps, TryOn/*, docs).
- `new/` — новые файлы (Posting/ClothingSizes*, PostingSize*, docs/SERVER_SIZES.md, SERVER_SIZE_TEMPLATES.md, каталог).
- `data/` — итоги агентов: карта кода, каталог типичных размеров, проверенные таблицы одежды и обуви, отчёты сборки,
  находки проверки (исправления не закончены).
Продолжить: `git apply wip/sizes/sizes-wip.patch && cp -r wip/sizes/new/* .` → пройти находки из data/*-5.json и
*-6.json → своя проверка → CI → коммит. Пачки: kliko-size-templates (wf_afb8d346-040), kliko-clothing-size-charts
(wf_a7ad26e5-9aa).
