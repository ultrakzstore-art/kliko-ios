import SwiftUI
import UIKit

/**
 3D-ОБЗОР В ПОДАЧЕ — ВХОД В ШАГЕ «ФОТО» (одна карточка и один модификатор в PostingSteps.swift).

 Карточка «3D-обзор · 5 фото» — под входом «Объявление с ИИ», над фото: только когда рубильник Config.обзор3D, сервер
 сказал on:true (ГотовностьОбзора3DПодачи) и раздел объявления — вещь или машина (РазделыОбзора3DПодачи). Показывает,
 что уже есть: «Снято 3 из 5», «360°-обзор готов», «Собираем 3D… 45%», «3D-модель готова», миниатюры ракурсов. Нажатие —
 полноэкранное окно съёмки (ЭкранСъёмкиОбзора3D). Долгое нажатие и VoiceOver — «Убрать 3D-обзор», в правке — ещё «Убрать
 из объявления», если у объявления уже есть 3D (my_items прислал model3d).

 Модификатор обзор3DВШагеФото — на всём шаге, даже когда карточки нет: спрашивает info, встречает подачу (чистая форма —
 прежние ракурсы новой подачи прочь), следит за публикацией (attach) и продолжает прерванные загрузку, сборку и привязку.
 */
struct ВходОбзора3DВШагеФото: View {
    @ObservedObject var модель: ПодачаМодель
    @ObservedObject private var готовность = ГотовностьОбзора3DПодачи.shared
    @ObservedObject private var хранилище = ХранилищеОбзора3DПодачи.shared
    @State private var открыт = false
    /// Вид открытого окна — запомнен при нажатии: пока окно открыто, карточка (и её fullScreenCover) держится, даже
    /// если готовность пропала (сервер ответил «не умею», info сказал on:false, сменилась сессия).
    @State private var видОкна: ВидОбзора3DПодачи? = nil
    @State private var кадры: [Int: UIImage] = [:]
    @State private var убираем = false

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    /// Вид карточки: окно открыто — тот, с которым его открыли; иначе — что говорит готовность (nil — карточки нет).
    private var видКарточки: ВидОбзора3DПодачи? {
        if открыт, let видОкна { return видОкна }
        return готовность.вид(для: модель.форма.раздел)
    }

    /// Подпись файлов ракурсов: миниатюры перечитываются, только когда сменились сами файлы, а не на каждый процент
    /// сборки или ответ загрузки (версия хранилища растёт и от них).
    private var подписьКадров: String {
        guard let з = хранилище.запись(модель) else { return "" }
        return з.папка + "|" + з.ракурсы.map { $0.файл + ":" + String($0.снят) }.joined(separator: "|")
    }

    var body: some View {
        if let вид = видКарточки {
            карточка(вид)
                .fullScreenCover(isPresented: $открыт) {
                    ЭкранСъёмкиОбзора3D(подача: модель, вид: видОкна ?? вид, закрыть: { открыт = false })
                }
                .task(id: подписьКадров) { await обновитьКадры() }
        }
    }

    private func открыть(_ вид: ВидОбзора3DПодачи) {
        видОкна = вид
        открыт = true
    }

    // MARK: Карточка

    private func карточка(_ вид: ВидОбзора3DПодачи) -> some View {
        let з = хранилище.запись(модель)
        let наСервере = хранилище.естьУОбъявления(модель)
        return Button {
            ОткликСайта.выбор()
            открыть(вид)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "rotate.3d")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(т("m3_entry_t"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(КраскаПодачи.текст)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(подпись(з, вид: вид, наСервере: наСервере))
                            .font(.caption)
                            .foregroundStyle(цветПодписи(з))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .accessibilityHidden(true)
                }
                if let з, з.снято > 0 { миниатюры(з) }
                if let з, з.собирается { полоса(з) }
                if з == nil && готовность.сборкаВозможна { строкаИИ }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.28), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(убираем)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button(т("m3_entry_open"), systemImage: "rotate.3d") { открыть(вид) }
            if з != nil {
                Button(т("m3_remove"), systemImage: "trash", role: .destructive) { убрать() }
            }
            if наСервере {
                Button(т("m3_remove_listing"), systemImage: "trash.slash", role: .destructive) { убратьИзОбъявления() }
            }
        }
        .accessibilityActions {
            if з != nil {
                Button(т("m3_remove")) { убрать() }
            }
            if наСервере {
                Button(т("m3_remove_listing")) { убратьИзОбъявления() }
            }
        }
    }

    /// Что сейчас с 3D-обзором этой подачи — одной строкой.
    private func подпись(_ з: ЗаписьОбзора3DПодачи?, вид: ВидОбзора3DПодачи, наСервере: Bool) -> String {
        let ключ = хранилище.ключЦели(модель)
        guard let з, з.снято > 0 else {
            if наСервере { return т("m3_entry_has") }
            return т(вид == .машина ? "m3_entry_s_car" : "m3_entry_s")
        }
        if let отказ = хранилище.отказЗагрузки[ключ] {
            return отказ.ракурс >= 0
                ? String(format: т("m3_angle_bad"), отказ.ракурс + 1, отказ.отказ.текст)
                : отказ.отказ.текст
        }
        if !з.всеСняты { return String(format: т("m3_entry_partial"), з.снято, РакурсОбзора3DПодачи.всего) }
        if з.собирается {
            if let заминка = хранилище.заминка[ключ] { return заминка }
            return String(format: т("m3_entry_building"), з.прогресс)
        }
        if хранилище.запускаем.contains(ключ) { return т("m3_stage_upload") }
        if з.готова { return т("m3_entry_done") }
        if з.неУдалась { return т("m3_entry_failed") }
        if модель.правка {
            return т(з.привязано.isEmpty ? "m3_entry_not_saved" : "m3_saved_listing")
        }
        return т("m3_entry_360")
    }

    private func цветПодписи(_ з: ЗаписьОбзора3DПодачи?) -> Color {
        let ключ = хранилище.ключЦели(модель)
        if хранилище.отказЗагрузки[ключ] != nil || з?.неУдалась == true { return КраскаПодачи.вниманиеТекст }
        if модель.правка, let з, з.всеСняты, з.привязано.isEmpty, !з.собирается { return КраскаПодачи.вниманиеТекст }
        return Theme.текстВторой
    }

    private func миниатюры(_ з: ЗаписьОбзора3DПодачи) -> some View {
        HStack(spacing: 6) {
            ForEach(РакурсОбзора3DПодачи.allCases) { р in
                let есть = з.ракурс(р).есть
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(КраскаПодачи.карточка)
                    if есть {
                        КартинкаРакурсаОбзора3D(картинка: кадры[р.rawValue],
                                                адрес: КартинкаРакурсаОбзора3D.адресРакурса(з, р.rawValue))
                            .padding(2)
                    } else {
                        Text(String(р.номер))
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .frame(width: 40, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(есть ? КраскаПодачи.хорошоТекст.opacity(0.5) : КраскаПодачи.линия, lineWidth: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func полоса(_ з: ЗаписьОбзора3DПодачи) -> some View {
        GeometryReader { место in
            ZStack(alignment: .leading) {
                Capsule().fill(КраскаПодачи.линия)
                Capsule()
                    .fill(Theme.зелёныйЯркий)
                    .frame(width: место.size.width * CGFloat(max(3, з.прогресс)) / 100)
                    .animation(ДвижениеСайта.прогресс, value: з.прогресс)
            }
        }
        .frame(height: 6)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    /// Пока ничего не снято и сервер собирает модели — «ИИ соберёт 3D-модель».
    private var строкаИИ: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            Text(т("m3_entry_ai"))
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(КраскаПодачи.хорошоТекст)
    }

    // MARK: Действия

    private func обновитьКадры() async {
        guard let з = хранилище.запись(модель), з.снято > 0 else {
            if !кадры.isEmpty { кадры = [:] }
            return
        }
        let новые = await ХранилищеОбзора3DПодачи.миниатюры(з, сторона: 160)
        guard !Task.isCancelled else { return }
        кадры = новые.картинки
    }

    private func убрать() {
        ОткликСайта.выбор()
        хранилище.убрать(модель)
        модель.показать(т("m3_removed"))
    }

    private func убратьИзОбъявления() {
        guard !убираем else { return }
        убираем = true
        Task { @MainActor in
            let удалено = await хранилище.убратьИзОбъявления(модель)
            убираем = false
            if удалено {
                ОткликСайта.успех()
            } else {
                ОткликСайта.предупреждение()
            }
            модель.показать(т(удалено ? "m3_removed_listing" : "m3_err_fail"))
        }
    }
}

// MARK: - Запуск на шаге «Фото»

extension View {
    /// Шаг «Фото»: info 3D-обзора, встреча подачи, слежка за публикацией и продолжение прерванного — даже без карточки.
    func обзор3DВШагеФото(модель: ПодачаМодель) -> some View {
        modifier(ЗапускОбзора3DВШагеФото(модель: модель))
    }
}

struct ЗапускОбзора3DВШагеФото: ViewModifier {
    let модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    func body(content: Content) -> some View {
        content.task {
            guard Config.обзор3D else { return }
            let хранилище = ХранилищеОбзора3DПодачи.shared
            хранилище.встретить(модель)
            хранилище.следить(за: модель)
            хранилище.возобновить(модель)
            await ГотовностьОбзора3DПодачи.shared.проверить()
        }
    }
}
