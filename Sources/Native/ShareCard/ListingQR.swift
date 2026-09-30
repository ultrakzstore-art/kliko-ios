import SwiftUI
import UIKit

/**
 QR-КОД ОБЪЯВЛЕНИЯ — своё окно из «Поделиться» (давняя просьба владельца: продавец распечатает код и положит рядом с
 товаром или покажет с экрана покупателю — тот наведёт камеру и сразу попадёт в объявление).

 У сайта отдельного QR объявления нет: код есть только внизу «Фото-карточки» (mkShareCard, «Наведи камеру на QR →») и на
 постере услуги. Сам код — как у сайта (_mkBuildQR): qrcode(0, "M"), тёмный #0b1f14 на белом, без знака в середине; здесь
 его рисует ПоделитьсяСайта.qr (CIQRCodeGenerator, уровень M, модули без сглаживания). Внутри — ссылка «Поделиться»
 (mkItemUrl сайта: /kz/<язык>/marketplace?item=<id> или ЧПУ-адрес буквенного номера), только без p= открытого фото:
 напечатанный код не должен зависеть от того, какое фото было на экране. Сеть не нужна.

 Окно: белая карточка (белая и в тёмной теме — иначе камера не прочтёт, а принтер напечатает серое) — «Kliko.kz»,
 крупный код с белым полем вокруг, «Наведите камеру — объявление откроется в Kliko», название и цена. Ниже «Поделиться
 QR-кодом»: та же карточка картинкой 1080 пикселей в ширину — в системный лист, а там печать, «Сохранить изображение»,
 AirDrop и мессенджеры. Своей кнопки «Сохранить в Фото» нет — её делает системный лист. Высота окна — по содержимому.

 Вход — плитка «QR-код» в листе «Поделиться» объявления (ЛистПоделитьсяСайта, SiteShare.swift): окно встаёт поверх
 листа, «Готово» возвращает к нему. Витрина продавца делится системным ShareLink, своего листа у неё нет — там кода нет.
 */
struct ЛистQRОбъявления: View {
    let данные: ДанныеОтправкиСайта

    @Environment(\.dismiss) private var закрыть
    @State private var код: UIImage? = nil
    @State private var неВышло = false

    init(данные: ДанныеОтправкиСайта) {
        self.данные = данные
    }

    private func т(_ ключ: String) -> String { ListingQRText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(т("title"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 14)
                КарточкаQRОбъявления(данные: данные, код: код)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
                    .frame(maxWidth: 340)
                Button { поделиться() } label: {
                    Label(т("share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .disabled(код == nil)
                .padding(.top, 16)
                Text(неВышло ? т("failed") : т("share_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Button(т("done")) { закрыть() }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 39)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationBackground(Theme.поверхность)
        .листПоВысоте()
        .onAppear {
            if код == nil { код = QRОбъявления.изображениеКода(данные) }
        }
    }

    /// Карточка картинкой — в системный лист (печать, «Сохранить изображение», мессенджеры). Не нарисовалась — подпись.
    private func поделиться() {
        guard let картинка = QRОбъявления.картинка(данные) else {
            ОткликСайта.предупреждение()
            withAnimation(ДвижениеСайта.смена) { неВышло = true }
            return
        }
        неВышло = false
        ПоделитьсяСайта.системныйЛист([картинка])
    }
}

/**
 Белая карточка кода: «Kliko.kz», QR с полем, подсказка, черта, название (две строки) и цена. Одна и та же в окне и на
 картинке для печати — что человек видит, то и уйдёт. Всегда светлая; цвета — как у постера сайта (#0b6b3c, #14312a).
 */
struct КарточкаQRОбъявления: View {
    let данные: ДанныеОтправкиСайта
    /// Код ссылки; nil — пока не нарисован: светлый квадрат того же размера (высота окна не прыгает).
    let код: UIImage?

    private var зелёный: Color { Color(uiColor: Theme.hex(0x0B6B3C)) }
    private func т(_ ключ: String) -> String { ListingQRText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "Kliko.kz")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(зелёный)
                .accessibilityHidden(true)
            квадрат
                .padding(.top, 8)
            Text(т("hint"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: Theme.hex(0x3F5A4E)))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Rectangle()
                .fill(Color(uiColor: Theme.hex(0xE6ECE8)))
                .frame(height: 1)
                .padding(.vertical, 14)
                .accessibilityHidden(true)
            Text(данные.название.isEmpty ? т("item") : данные.название)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color(uiColor: Theme.hex(0x14312A)))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(данные.строкаЦены)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(зелёный)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    /// Код до 260 точек с белым полем 10 вокруг: без тихой зоны у края (у сайта q=4) камера узнаёт код хуже.
    @ViewBuilder
    private var квадрат: some View {
        if let код {
            Image(uiImage: код)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 260)
                .padding(10)
                .accessibilityLabel(т("a11y"))
                .accessibilityAddTraits(.isImage)
        } else {
            Color(uiColor: Theme.hex(0xF4F8F6))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 260)
                .padding(10)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Код и картинка

enum QRОбъявления {
    /// Ссылка кода — mkItemUrl сайта без p= открытого фото.
    static func адрес(_ данные: ДанныеОтправкиСайта) -> URL {
        guard данные.номерФото > 0 else { return данные.адрес }
        let без = ДанныеОтправкиСайта(id: данные.id, название: данные.название, цена: данные.цена,
                                      состояние: данные.состояние, фото: данные.фото, услуга: данные.услуга)
        return без.адрес
    }

    /// QR ссылки: уровень M, #0b1f14 на белом, модуль 12 пикселей — дальше увеличивается без сглаживания.
    static func изображениеКода(_ данные: ДанныеОтправкиСайта) -> UIImage? {
        ПоделитьсяСайта.qr(адрес(данные).absoluteString, модуль: 12)
    }

    /// Карточка для печати и отправки: 360 точек втрое плотнее — 1080 пикселей в ширину, белый непрозрачный лист.
    @MainActor
    static func картинка(_ данные: ДанныеОтправкиСайта) -> UIImage? {
        guard let код = изображениеКода(данные) else { return nil }
        let вид = КарточкаQRОбъявления(данные: данные, код: код)
            .frame(width: 360)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .dynamicTypeSize(.large)
        let рисовальщик = ImageRenderer(content: вид)
        рисовальщик.scale = 3
        рисовальщик.isOpaque = true
        return рисовальщик.uiImage
    }
}

// MARK: - Тексты

/// Тексты окна QR на языке телефона — kk/ru/en/ar (у сайта такого окна нет).
enum ListingQRText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "title": "QR-код объявления", "hint": "Наведите камеру — объявление откроется в Kliko",
            "a11y": "QR-код ссылки на объявление", "item": "Объявление",
            "share": "Поделиться QR-кодом", "share_hint": "Распечатать, сохранить или отправить — в следующем окне",
            "failed": "Не получилось, попробуйте ещё раз", "done": "Готово"
        ],
        "kk": [
            "title": "Хабарландырудың QR-коды", "hint": "Камераны бағыттаңыз — хабарландыру Kliko-да ашылады",
            "a11y": "Хабарландыру сілтемесінің QR-коды", "item": "Хабарландыру",
            "share": "QR-кодпен бөлісу", "share_hint": "Басып шығару, сақтау не жіберу — келесі терезеде",
            "failed": "Болмады, қайта көріңіз", "done": "Дайын"
        ],
        "en": [
            "title": "Listing QR code", "hint": "Point your camera — the listing opens in Kliko",
            "a11y": "QR code of the listing link", "item": "Listing",
            "share": "Share QR code", "share_hint": "Print, save or send it in the next window",
            "failed": "Something went wrong, try again", "done": "Done"
        ],
        "ar": [
            "title": "رمز QR للإعلان", "hint": "وجّه الكاميرا — سيُفتح الإعلان في Kliko",
            "a11y": "رمز QR لرابط الإعلان", "item": "إعلان",
            "share": "مشاركة رمز QR", "share_hint": "اطبعه أو احفظه أو أرسله من النافذة التالية",
            "failed": "تعذّر ذلك، حاول مرة أخرى", "done": "تم"
        ]
    ]
}
