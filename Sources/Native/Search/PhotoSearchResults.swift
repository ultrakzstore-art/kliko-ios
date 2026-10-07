import SwiftUI
import UIKit

/**
 ПОИСК ПО ФОТО ПОСЛЕ СНИМКА (владелец 29.09.2026): «Ищем похожие…» поверх фото, затем сетка карточек ленты
 «Похожие на ваше фото» с «Снять ещё», или ошибка с «Повторить». Модель и запросы — PhotoSearch.swift.
 */

/// Фото на тёмном фоне, бегущая зелёная полоса по нему и «Ищем похожие…» (Kliko AI) снизу.
struct ЭкранРаспознаванияФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var бег = false

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    КруглаяКнопкаФото(значок: "xmark", подпись: т("ps_cancel_search")) { модель.снятьЕщё() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                фото
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                панель
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .onAppear { if !тихо { бег = true } }
    }

    @ViewBuilder
    private var фото: some View {
        if let превью = модель.превью {
            Image(uiImage: превью)
                .resizable()
                .scaledToFit()
                .overlay { развёртка }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .overlay {
                    УголкиПоискаФото(длина: 30, цвет: Theme.зелёныйЯркий, толщина: 3.5)
                        .padding(-6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(т("ps_photo"))
        } else {
            Spacer(minLength: 0)
        }
    }

    /// Бегущая сверху вниз зелёная полоса по фото (_mkPhotoProgress сайта); без движения — её нет.
    private var развёртка: some View {
        GeometryReader { место in
            if !тихо {
                LinearGradient(stops: [Gradient.Stop(color: Theme.зелёныйЯркий.opacity(0), location: 0),
                                       Gradient.Stop(color: Theme.зелёныйЯркий.opacity(0.4), location: 0.6),
                                       Gradient.Stop(color: Color.white.opacity(0.55), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                    .offset(y: бег ? место.size.height : -70)
                    .animation(.linear(duration: 1.6).repeatForever(autoreverses: false), value: бег)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var панель: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ИскраПоискаФото(тихо: тихо)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("ps_searching"))
                        .font(.headline)
                        .foregroundStyle(Color.white)
                    Text(т("ps_searching_sub"))
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            ПолосаПоискаФото(тихо: тихо)
        }
        .padding(16)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Значок Kliko AI — «искры» в зелёном круге, мягко пульсируют.
private struct ИскраПоискаФото: View {
    let тихо: Bool
    @State private var пульс = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .scaleEffect(пульс ? 1.08 : 1)
            .onAppear {
                guard !тихо else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { пульс = true }
            }
            .accessibilityHidden(true)
    }
}

/// Бегущий отрезок 40 % ширины (.mk-pprog-bar сайта); без движения — ровная полоса наполовину.
private struct ПолосаПоискаФото: View {
    let тихо: Bool
    @State private var бег = false

    var body: some View {
        GeometryReader { место in
            let ширина = место.size.width
            Capsule()
                .fill(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный2], startPoint: .leading,
                                     endPoint: .trailing))
                .frame(width: тихо ? ширина * 0.5 : ширина * 0.4)
                .offset(x: тихо ? 0 : (бег ? ширина : -ширина * 0.4))
        }
        .frame(height: 6)
        .background(Color.white.opacity(0.14))
        .clipShape(Capsule())
        .onAppear {
            guard !тихо else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) { бег = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Похожие

/// «Похожие на ваше фото»: фото и что распознал Kliko AI, «Все в ленте», сетка ListingCard; снизу «Снять ещё».
struct ЭкранПохожихПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    @Environment(\.dynamicTypeSize) private var размерТекста

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                шапка
                    .padding(.horizontal, ListingCard.поле)
                if модель.товары.isEmpty {
                    пусто
                } else {
                    LazyVGrid(columns: ListingCard.сетка(размерТекста), spacing: ListingCard.зазор) {
                        ForEach(модель.товары) { товар in
                            NavigationLink(value: товар) { ListingCard(товар: товар) }
                                .buttonStyle(.plain)
                                .сердечкоИзбранного(товар)
                                .поделитьсяНаКарточке(товар)
                                .менюКарточкиОбъявления(товар)
                        }
                    }
                    .padding(.horizontal, ListingCard.поле)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("ps_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { модель.закрыть() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel(т("close"))
            }
        }
        .overlay(alignment: .bottom) {
            снятьЕщё
                .padding(.bottom, 16)
        }
    }

    private var шапка: some View {
        HStack(alignment: .center, spacing: 14) {
            if let превью = модель.превью {
                Image(uiImage: превью)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
                    .accessibilityLabel(т("ps_photo"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(т("ps_results"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.зелёный2)
                        .accessibilityHidden(true)
                    Text(String(format: т("ps_ai_saw"), модель.запрос))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                }
                .font(.subheadline.weight(.semibold))
                if !модель.товары.isEmpty {
                    HStack(spacing: 10) {
                        Text(String(format: т("ps_count"), модель.всего ?? модель.товары.count))
                            .font(.footnote)
                            .foregroundStyle(Theme.текстВторой)
                        Button { модель.вЛенту() } label: {
                            Text(т("ps_in_feed"))
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.зелёный2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.оттенокАкцента, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(НажатиеКнопкиФото())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    /// Ничего не нашлось: подсказка про ракурс и «Все в ленте» (поиск по тому же запросу в ленте).
    private var пусто: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .frame(width: 68, height: 68)
                .background(Theme.мята, in: Circle())
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(т("ps_empty"))
                .font(.headline)
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
            Text(т("ps_empty_hint"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)
            if !модель.запрос.isEmpty {
                ЗелёнаяКнопкаФото(заголовок: т("ps_in_feed"), значок: "list.bullet", контурная: true) {
                    модель.вЛенту()
                }
                .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    /// Плавающая зелёная капсула «Снять ещё» — снова камера в том же окне.
    private var снятьЕщё: some View {
        Button { модель.снятьЕщё() } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .accessibilityHidden(true)
                Text(т("ps_again"))
            }
            .font(.body.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .frame(minHeight: 50)
            .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                       startPoint: .leading, endPoint: .trailing), in: Capsule())
            .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото())
    }
}

// MARK: - Ошибка

/// Не распознали, нет связи или не то изображение: затемнённое фото, текст, «Повторить», «Снять ещё», галерея.
struct ЭкранОшибкиПоискаФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let текст: String

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let превью = модель.превью {
                Image(uiImage: превью)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18)
                    .opacity(0.35)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                HStack {
                    КруглаяКнопкаФото(значок: "xmark", подпись: т("close")) { модель.закрыть() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                ScrollView {
                    карточка
                        .padding(.horizontal, 24)
                        .padding(.vertical, 40)
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var карточка: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.ценаСкидка)
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.1), in: Circle())
                .padding(.bottom, 16)
                .accessibilityHidden(true)
            Text(текст)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            Text(т("ps_retry_hint"))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            if модель.превью != nil {
                ЗелёнаяКнопкаФото(заголовок: т("ps_retry_btn"), значок: "arrow.clockwise") { модель.повторить() }
                    .padding(.bottom, 10)
            }
            ЗелёнаяКнопкаФото(заголовок: т("ps_again"), значок: "camera.fill", контурная: модель.превью != nil,
                              наТёмном: true) { модель.снятьЕщё() }
                .padding(.bottom, 6)
            Button { модель.открытьГалерею() } label: {
                Text(т("ps_gallery"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
    }
}
