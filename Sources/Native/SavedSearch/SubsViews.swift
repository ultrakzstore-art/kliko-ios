import SwiftUI

/**
 ПОДПИСКА НА ПРОДАВЦА НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ И В КАБИНЕТЕ — ЭТАП 36 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 На странице объявления сайта под карточкой продавца (.mk-msc) стоит .mk-sfollow: широкая кнопка .mk-sfbtn с колокольчиком
 «Подписаться на продавца», а после нажатия — зелёная «Вы подписаны» (mkSetFollowBtn: фон и рамка var(--mk-green), текст
 белый); число подписчиков — в строке карточки «7 сделок · 12 подписчиков · с 2026 г.» (mkSellerFolHtml). На своём
 объявлении кнопки нет (getMkMe() === seller_id). Кебаб «Заблокировать» и «Пожаловаться» рядом с ней — не подписки, их
 здесь нет. Краски — динамические Theme, как у остальных экранов сайта.

 В кабинете продавцы, на которых подписан человек, — разделом «Мои подписки · Продавцы», как «Продавцы» в блоке подписок
 сайта (mkRenderFavSubs): нажатие — страница продавца на сайте, смахивание «Отписаться» — mkFavSubUnfollow.
 */
struct ПродавецСПодпиской: View {
    let товар: Listing
    let продавецID: String
    @ObservedObject private var синхрон = СинхронПодписок.shared

    init(товар: Listing, продавецID: String) {
        self.товар = товар
        self.продавецID = продавецID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            КарточкаПродавцаСайта(товар: товар, подписчики: подписчики)
            if синхрон.мой != продавецID {
                КнопкаПодпискиНаПродавца(продавецID: продавецID, имя: товар.продавец ?? "")
            }
        }
        /* mkSellerActionsSync: подписан ли и сколько подписчиков — при показе карточки. */
        .onAppear { синхрон.узнать(продавца: продавецID) }
    }

    /// Свежее число с сайта (status, follow), пока его нет — seller_followers объявления.
    private var подписчики: Int? {
        синхрон.подписчиков(продавецID) ?? товар.подписчикиПродавца
    }
}

/// .mk-sfbtn: высота от 46, скругление --r-md (14), рамка 1 --mk-line на --mk-surf, жирный текст --fs-base; подписан —
/// заливка и рамка --mk-green, текст белый.
struct КнопкаПодпискиНаПродавца: View {
    let продавецID: String
    let имя: String
    @ObservedObject private var синхрон = СинхронПодписок.shared

    init(продавецID: String, имя: String) {
        self.продавецID = продавецID
        self.имя = имя
    }

    private var подписан: Bool { синхрон.подписан(на: продавецID) }

    var body: some View {
        Button {
            синхрон.нажали(продавца: продавецID, имя: имя)
        } label: {
            надпись
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .animation(.easeOut(duration: 0.15), value: подписан)
        .accessibilityLabel(SubsText.т(подписан ? "subscribed" : "follow_seller"))
        .accessibilityHint(подписан ? SubsText.т("unfollow") : "")
        .accessibilityAddTraits(подписан ? .isSelected : [])
    }

    private var надпись: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return HStack(spacing: 8) {
            Image(systemName: подписан ? "bell.fill" : "bell")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(SubsText.т(подписан ? "subscribed" : "follow_seller"))
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(подписан ? Color.white : Theme.текст)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(подписан ? Theme.зелёный : Theme.поверхность, in: форма)
        .overlay {
            форма.strokeBorder(подписан ? Theme.зелёный : Theme.линия, lineWidth: 1)
        }
        .contentShape(форма)
    }
}

/// Раздел кабинета «Мои подписки · Продавцы». Пусто — раздела нет.
struct РазделПодписокНаПродавцов: View {
    @ObservedObject private var синхрон = СинхронПодписок.shared
    /// Открыть страницу сайта в веб-обёртке — как остальные строки кабинета.
    let открыть: (URL) -> Void

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        if !синхрон.продавцы.isEmpty {
            Section {
                ForEach(синхрон.продавцы) { продавец in
                    строка(продавец)
                }
            } header: {
                Text(SubsText.т("sellers_title"))
            } footer: {
                Text(SubsText.т("sellers_footer"))
            }
        }
    }

    private func строка(_ продавец: СинхронПодписок.Продавец) -> some View {
        Button {
            if let адрес = СинхронПодписок.страницаПродавца(продавец.id) { открыть(адрес) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "storefront")
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(продавец.имя.isEmpty ? SubsText.т("seller") : продавец.имя)
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityHint(SubsText.т("open_seller"))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                синхрон.отписаться(продавец)
            } label: {
                Text(SubsText.т("unfollow"))
            }
        }
    }
}
