I wrote both files and committed nothing.

**1. `/home/user/kliko-ios/docs/SERVER_SIZES.md`** (new, 651 lines, about 280 of them tables). It follows the style of `SERVER_DIMENSIONS.md`: owner's words first, then a "Что / Где / Кто" table, numbered sections and a checklist.
- **Section 1, tables.**
  - 1.1 maps each site section to its tabs, which tab opens first, and the system the `storage` value is in.
  - 1.2 has all 13 clothing and shoe tables. I generated them by script from `ТаблицыРазмеровОдежды` in `ClothingSizes.swift`, so they match the app's data. MEX and см are merged into one column because the values are equal; kids' EU and RU are merged the same way. Each table has a one-line note.
  - 1.3 proposes `rules.sizes = {on, store, tables, cats}` in `app_post_schema.php`, plus a `size_sys` key on the `storage` field. Jeans and bra tables are built as pairs from the keys.
  - It states plainly that app 1.12 only uses its built-in tables. Reading `rules.sizes` would come in the next build, once the site developer confirms the format.
  - Tyres and screen diagonals are pointed to `docs/SERVER_SIZE_TEMPLATES.md` (`rules.dims`), which the neighbouring batch has now created.
- **Section 2, the size field and storage.**
  - Which system the site value is in, with a request to confirm it or set `size_sys`, and to send the current field options.
  - The app's matching order for picking the field value.
  - Optional `size_sys` and `size_all` in `submit` and `edit_item`, and how to return them in `api/listings.php` and `my_items`.
  - The "Размер: …" line in the description as a temporary measure. It includes 10 sample lines and a parsing regex; both were checked by script against the lines for every row of every table.
  - What changes once the site sets `store: true`.
- **Section 3, the site form.** System switch, chip grid with fixed 40px chips and 5/4/3/2 columns, the size tag, the ±½ note, animation timings, `prefers-reduced-motion`, and the interface text in ru, kk, en and ar taken from `ClothingSizesText.swift`.
- **Section 4, the buyer side.** Size tag in the listing window, a "more in this size" link, size chip on the card, and a feed filter `size=<code>:<value>` that accepts any system.
- **Section 5, "dopamine".** Nine techniques from the brief: instant feedback, visible progress, ready-made templates, a short celebration on publishing, "Похожие у других продавцов", an honest "Ваше объявление увидят …" count, plus soft errors, a first-views notification and performance rules. It ends with a list of forbidden dark patterns and no paid offers.
- **Sections 6 and 7.** A checklist for the site developer and a list of the related app files.

**2. `/tmp/claude-0/-home-user-kliko-ios/169a1871-7ac5-51e2-a65a-3428af4626f2/scratchpad/ultra-site-sizes-clothing.md`** (67 lines, one page). This is the short brief for the owner: six points, a report table, and a link to `docs/SERVER_SIZES.md`. Because nothing is committed, it says to attach that file if it isn't in `main` yet.

Several things in the contract depend on the site developer or on later app work:
- **Site field options are unverified.** The real options of the site's "Размер" field are still unknown. The contract asks the site developer to confirm the systems or set `size_sys`.
- **Not in the app yet.** Sending `size_sys`/`size_all` and reading `rules.sizes` are proposals only. The buyer's size tag is built in the app but not yet placed in the listing window.
- **Design choices beyond the brief.** The `size_sys` key on the schema field, the `size=` filter syntax and the 200-character limit on `size_all` are my own choices.