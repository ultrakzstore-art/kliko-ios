import SwiftUI
import PhotosUI

/**
 ФОТО ОДНОЙ СТРОКИ ИМПОРТА — лист «Фото товара» (_aiOpenPhotoPicker сайта, js/cabinet-aiimport.min.js).

 У сайта: шапка «Фото товара «название»» с кнопками «Загрузить» (aiRowPhotoUpload — выбор нескольких снимков,
 uploadImageSmart по одному, каждый — в загруженные _aiPhotos и, пока их меньше 8, в строку; плашки «Загружаю фото…» и
 «Фото добавлено») и «Готово», подпись и сетка уже загруженных за этот заход снимков (_aiPickGridHTML): нажатие
 привязывает или снимает фото (_aiPickToggle, «Не больше 8 фото на товар»), у привязанного — галочка, у чужого —
 «№N» строки-владельца (_aiPhotoOwner). Здесь то же, и сверху — фото самой строки с «×» (_aiPhotoDel сайта убирает
 их по одному из ячейки строки), и ход загрузки: кольцо, «i из n».

 Загрузка — ИмпортAPI.загрузитьФото: сжатие и водяной знак ОбработкаФото, upload_photo с csrf и миниатюра, как
 uploadImageSmart сайта.
 */
struct ФотоСтрокиИмпорта: View {
    @ObservedObject var модель: ИмпортМодель
    let номер: UUID

    @Environment(\.dismiss) private var закрыть
    @State private var выбор: [PhotosPickerItem] = []
    @State private var читаем = false
    @State private var плашка: String? = nil
    @State private var плашкаНомер = 0

    init(модель: ИмпортМодель, номер: UUID) {
        self.модель = модель
        self.номер = номер
    }

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { ИмпортText.т(ключ, з) }

    private var строка: СтрокаИмпорта? { модель.строки.first { $0.id == номер } }
    private var фото: [String] { строка?.фото ?? [] }
    private var загрузка: ЗагрузкаФотоСтроки? { модель.загрузкиФото[номер] }
    private var сетка: [GridItem] { [GridItem(.adaptive(minimum: 88), spacing: 8)] }
    private var занято: Bool { загрузка != nil || читаем }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    шапка
                    загрузить
                    if let загрузка { ход(загрузка) }
                    if !фото.isEmpty { своиФото }
                    загруженные
                }
                .padding(16)
                .мерилоФормы()
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("ph_t"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("ph_done")) { закрыть() }
                        .fontWeight(.bold)
                }
            }
            .overlay(alignment: .bottom) {
                if let плашка {
                    ПлашкаКошелька(текст: плашка)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .tint(Theme.акцент)
        /* По высоте содержимого: мало фото — лист ниже, много — до полного. */
        .листПоВысоте()
        .onChange(of: выбор) { _, элементы in
            guard !элементы.isEmpty else { return }
            читаем = true
            Task {
                var снимки: [Data] = []
                for элемент in элементы {
                    if let данные = try? await элемент.loadTransferable(type: Data.self) { снимки.append(данные) }
                }
                выбор = []
                читаем = false
                модель.загрузитьФото(снимки, строка: номер)
            }
        }
        .onChange(of: модель.весть) { _, весть in
            guard let весть else { return }
            показать(весть.текст, долго: весть.долго)
        }
        .откликВыбора(фото)
    }

    // MARK: Шапка и «Загрузить»

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let строка, !строка.название.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("«" + String(строка.название.prefix(34)) + "»")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
            }
            Text(т("ph_sub"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var загрузить: some View {
        PhotosPicker(selection: $выбор, maxSelectionCount: ИмпортМодель.фотоНаТовар, matching: .images) {
            HStack(spacing: 8) {
                if занято {
                    SiteSpinner.мелкийБелый
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(т("ph_up"))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.акцент, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .opacity(занято ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(занято || строка == nil)
    }

    private func ход(_ з: ЗагрузкаФотоСтроки) -> some View {
        let подпись = т("ph_prog", ["i": String(min(з.всего, з.номер + 1)), "n": String(з.всего)])
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(т("ph_loading"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 6)
                Text(подпись)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .monospacedDigit()
            }
            ProgressView(value: з.общая)
                .tint(Theme.акцент)
                .accessibilityValue(String(Int(з.общая * 100)) + "%")
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .transition(.opacity)
    }

    // MARK: Фото строки

    private var своиФото: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("ph_this", ["n": String(фото.count), "m": String(ИмпортМодель.фотоНаТовар)]))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
            LazyVGrid(columns: сетка, spacing: 8) {
                ForEach(фото, id: \.self) { адрес in
                    ZStack(alignment: .topTrailing) {
                        плитка(адрес)
                        Button {
                            withAnimation(ДвижениеСайта.выбор) { модель.убратьФото(адрес, строка: номер) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.7), in: Circle())
                                .overlay { Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(т("ph_del"))
                    }
                    .overlay(alignment: .bottomLeading) {
                        if адрес == фото.first {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 18, height: 18)
                                .background(Theme.акцент, in: Circle())
                                .padding(4)
                                .accessibilityHidden(true)
                        }
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .animation(ДвижениеСайта.вставкаСписка, value: фото)
    }

    // MARK: Загруженные (_aiPickGridHTML)

    @ViewBuilder
    private var загруженные: some View {
        let пул = модель.пулФото
        VStack(alignment: .leading, spacing: 8) {
            Text(т("ph_pool"))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
            if пул.isEmpty {
                Text(т("ph_empty"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .padding(.horizontal, 12)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            } else {
                LazyVGrid(columns: сетка, spacing: 8) {
                    ForEach(пул, id: \.self) { адрес in
                        выборФото(адрес)
                    }
                }
            }
        }
    }

    private func выборФото(_ адрес: String) -> some View {
        let привязано = фото.contains(адрес)
        let владелец = привязано ? nil : модель.владелецФото(адрес, кроме: номер)
        return Button {
            withAnimation(ДвижениеСайта.выбор) { модель.переключитьФото(адрес, строка: номер) }
        } label: {
            плитка(адрес)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(привязано ? Theme.акцент : Theme.линия, lineWidth: привязано ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if привязано {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .frame(width: 22, height: 22)
                            .background(Theme.акцент, in: Circle())
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let владелец {
                        Text(т("ph_owner", ["n": String(владелец)]))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.62), in: Capsule())
                            .padding(5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(строка == nil)
        .accessibilityLabel(т("ph_t"))
        .accessibilityValue(владелец.map { т("ph_owner_a11y", ["n": String($0)]) } ?? "")
        .accessibilityAddTraits(привязано ? [.isSelected] : [])
    }

    private func плитка(_ адрес: String) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { МиниатюраИмпорта(адрес: адрес) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private func показать(_ текст: String, долго: Bool) {
        плашкаНомер += 1
        let свой = плашкаНомер
        withAnimation(ДвижениеСайта.появление) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: долго ? 4_200_000_000 : 2_800_000_000)
            guard свой == плашкаНомер else { return }
            withAnimation(ДвижениеСайта.уход) { плашка = nil }
        }
    }
}

/// Миниатюра фото импорта: адрес сайта (относительный — от Config.apiBase) или внешний; не открылась — заглушка
/// (onerror сайта прячет картинку).
struct МиниатюраИмпорта: View {
    let адрес: String

    var body: some View {
        AsyncImage(url: Config.url(адрес)?.absoluteURL, transaction: Transaction(animation: ДвижениеСайта.появление)) { фаза in
            switch фаза {
            case .success(let картинка):
                картинка.resizable().scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.текстВторой.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.поверхность2)
            default:
                Theme.поверхность2
            }
        }
        .accessibilityHidden(true)
    }
}

/// Кольцо хода загрузки фото строки и «i из n» под ним — поверх затемнённой миниатюры.
struct КольцоЗагрузкиИмпорта: View {
    let доля: Double
    let подпись: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.04, min(1, доля)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(ДвижениеСайта.прогресс, value: доля)
            }
            .frame(width: 24, height: 24)
            Text(подпись)
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundStyle(Color.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подпись)
        .accessibilityValue(String(Int(доля * 100)) + "%")
    }
}
