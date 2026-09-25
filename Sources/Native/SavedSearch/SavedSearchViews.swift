import SwiftUI
import UIKit
import UserNotifications

/**
 Раздел кабинета «Сохранённые поиски» (этап 12): список со свайпом «Удалить»; нажатие — лента с этим поиском, через
 роутер ссылок этапа 8, как из уведомления. Под списком — как работает проверка и что ей мешает: запрещённые
 уведомления или выключенное «Обновление контента» в Настройках iPhone.
 */
struct РазделСохранённыхПоисков: View {
    @ObservedObject private var хранилище = SavedSearchStore.shared
    /// Разрешены ли уведомления — кабинет уже спрашивает систему (ДанныеТелефона.статусУведомлений). nil — не знаем.
    let уведомления: UNAuthorizationStatus?

    init(уведомления: UNAuthorizationStatus?) {
        self.уведомления = уведомления
    }

    var body: some View {
        Section {
            if хранилище.поиски.isEmpty {
                Text(SavedSearchText.т("empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(хранилище.поиски) { поиск in
                    Button {
                        WebBridge.shared.открытьЭкран(.найти(поиск.искомое), запасной: nil)
                    } label: {
                        строка(поиск)
                    }
                    .accessibilityHint(SavedSearchText.т("open_hint"))
                }
                .onDelete { места in хранилище.убрать(места: места) }
            }
        } header: {
            Text(SavedSearchText.т("title"))
        } footer: {
            Text(подпись)
        }
    }

    private func строка(_ поиск: СохранённыйПоиск) -> some View {
        HStack(spacing: 12) {
            Image(systemName: поиск.искомое.текст.isEmpty ? "square.grid.2x2" : "magnifyingglass")
                .foregroundStyle(Theme.green2)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(поиск.название)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(когдаПроверен(поиск))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func когдаПроверен(_ поиск: СохранённыйПоиск) -> String {
        guard let когда = поиск.проверен else { return SavedSearchText.т("not_checked") }
        return String(format: SavedSearchText.т("checked"), Self.относительно.localizedString(for: когда, relativeTo: Date()))
    }

    /// Сначала — что мешает проверке (только если есть что проверять), потом — как она работает.
    private var подпись: String {
        var части: [String] = []
        if !хранилище.поиски.isEmpty {
            if уведомления == .denied { части.append(SavedSearchText.т("notif_off")) }
            if UIApplication.shared.backgroundRefreshStatus != .available { части.append(SavedSearchText.т("refresh_off")) }
        }
        части.append(SavedSearchText.т("footer"))
        return части.joined(separator: "\n\n")
    }

    /// «2 часа назад» — на языке телефона, как остальные тексты, а не на языке региона.
    private static let относительно: RelativeDateTimeFormatter = {
        let ф = RelativeDateTimeFormatter()
        ф.unitsStyle = .full
        ф.dateTimeStyle = .named
        ф.locale = Locale(identifier: Locale.preferredLanguages.first ?? "ru")
        return ф
    }()
}
