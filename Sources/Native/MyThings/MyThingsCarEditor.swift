import SwiftUI
import UIKit

/**
 «МОЁ» — РЕДАКТОР МАШИНЫ ГАРАЖА (лист в своей навигации [ШагАвтоподбора]).

 Марка → модель (пикеры «Подойдут ли?») → год (ВыборГодаМоего) → справочник посадки: нашёл — назад к машине, нет —
 параметры колёс вручную (ПараметрыКолёсМоего). Ниже — фото сбоку с кольцами колёс (тащатся пальцем), своё название,
 «Сделать главной», «Удалить машину». Сохраняется само на каждое изменение; «Готово» закрывает.
 */

// MARK: - Редактор машины

/// Модель листа машины: путь навигации и итог справочника для выбранной машины («ищем / нет / сеть»).
@MainActor
final class МодельРедактораМашиныМоего: ObservableObject {
    let id: UUID
    @Published var путь: [ШагАвтоподбора] = []
    @Published private(set) var ищем = false
    @Published private(set) var молчание: ГаражАвтоподбора.МолчаниеАвтоподбора? = nil

    init(id: UUID) {
        self.id = id
    }

    /// Выбран год (или «Не помню год»): справочник нашёл — назад к машине, нет — параметры колёс вручную.
    func выбрать(_ авто: МашинаАвтоподбора) {
        ОткликСайта.выбор()
        ищем = true
        молчание = nil
        let id = self.id
        Task { @MainActor [weak self] in
            let итог = await МоёХранилище.shared.выбратьАвто(id, авто)
            guard let self else { return }
            self.ищем = false
            let своиЕсть = МоёХранилище.shared.машина(id)?.посадка != nil
            switch итог {
            case .some(.есть):
                self.путь = []
                ОткликСайта.успех()
            case .some(.нет):
                self.молчание = .нет
                self.путь = своиЕсть ? [] : [.параметрыМашины]
            case .some(.сеть):
                self.молчание = .сеть
                self.путь = своиЕсть ? [] : [.параметрыМашины]
            case .none:
                break
            }
        }
    }
}

struct РедакторМашиныМоего: View {
    @StateObject private var модель: МодельРедактораМашиныМоего
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dismiss) private var закрыть
    @State private var имя = ""
    @State private var спроситьУдалить = false
    @State private var спроситьФото = false
    @State private var съёмка = false
    @State private var изГалереи = false

    init(id: UUID) {
        _модель = StateObject(wrappedValue: МодельРедактораМашиныМоего(id: id))
    }

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }
    private func а(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var машина: МашинаМоего? { хранилище.машина(модель.id) }

    var body: some View {
        NavigationStack(path: $модель.путь) {
            корень
                .navigationTitle(машина?.заголовок ?? т("my_garage"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(т("my_done")) { закрыть() }
                    }
                }
                .navigationDestination(for: ШагАвтоподбора.self) { шаг in
                    экранШага(шаг)
                }
        }
        .tint(Theme.акцент)
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $съёмка) {
            КамераШаблонаМоего(шаблон: .машинаСбоку, начатьСГалереи: изГалереи) { снимок in
                await МоёХранилище.shared.сохранитьФотоМашины(модель.id, готовое: снимок.готовое,
                                                              колёса: снимок.колёса, люди: снимок.люди,
                                                              шаблон: снимок.шаблон)
            }
        }
        .confirmationDialog(т("my_car_remove_q"), isPresented: $спроситьУдалить, titleVisibility: .visible) {
            Button(т("my_delete"), role: .destructive) {
                хранилище.удалитьМашину(модель.id)
                закрыть()
            }
            Button(т("my_cancel"), role: .cancel) {}
        }
        .confirmationDialog(т("my_car_photo_del"), isPresented: $спроситьФото, titleVisibility: .visible) {
            Button(т("my_delete"), role: .destructive) {
                withAnimation(ДвижениеСайта.смена) { хранилище.удалитьФотоМашины(модель.id) }
            }
            Button(т("my_cancel"), role: .cancel) {}
        }
        .onAppear { имя = машина?.имя ?? "" }
    }

    @ViewBuilder
    private var корень: some View {
        if let машина {
            ScrollView {
                VStack(spacing: 14) {
                    карточкаМашины(машина)
                    карточкаКолёс(машина)
                    карточкаФото(машина)
                    карточкаИмени
                    кнопки(машина)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .animation(ДвижениеСайта.смена, value: машина)
                .animation(ДвижениеСайта.смена, value: модель.ищем)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
        } else {
            Theme.фонСтраницы
                .ignoresSafeArea()
        }
    }

    private func карточкаМашины(_ машина: МашинаМоего) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("my_car_pick"), значок: "car.fill")
            NavigationLink(value: ШагАвтоподбора.марка) {
                HStack(spacing: 10) {
                    Text(машина.авто?.подпись ?? т("my_car_pick"))
                        .font(.headline)
                        .foregroundStyle(машина.авто == nil ? Theme.акцент : Theme.текст)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    СтрелкаСтрокиКабинета()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
        }
        .карточкаМоего()
    }

    private func карточкаКолёс(_ машина: МашинаМоего) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ЗаголовокМоего(т("my_car_wheels"), значок: "circle.circle")
                Spacer(minLength: 0)
                if модель.ищем {
                    SiteSpinner(размер: 16, толщина: 2, стоит: ДвижениеСайта.тихо)
                        .accessibilityLabel(а("af_car_searching"))
                }
            }
            if let посадка = машина.посадка {
                СводкаМашиныАвтоподбора(машина: машина.авто, посадка: посадка)
                МалаяКнопкаАвтоподбора(заголовок: а("af_car_edit"), значок: "slider.horizontal.3") {
                    модель.путь.append(.параметрыМашины)
                }
            } else {
                if модель.ищем || модель.молчание != nil {
                    Text(а(модель.ищем ? "af_car_searching"
                           : (модель.молчание == .сеть ? "af_car_no_net" : "af_car_not_found")))
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ЗелёнаяКнопкаФото(заголовок: т("my_car_wheels_set"), значок: "slider.horizontal.3", контурная: true) {
                    модель.путь.append(.параметрыМашины)
                }
                .disabled(модель.ищем)
            }
            Text(т("my_car_ref_note"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .карточкаМоего()
    }

    private func карточкаФото(_ машина: МашинаМоего) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("my_car_photo"), значок: "camera")
            if let фото = машина.фото {
                ФотоСКолёсамиМоего(фото: фото) { колёса in
                    хранилище.задатьКолёса(модель.id, колёса)
                }
                Text(т("my_wheels_hint"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                if фото.люди == true {
                    Label(т("my_check_people"), systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.оранжевый)
                }
                ПотокЧипов(зазор: 8) {
                    МалаяКнопкаАвтоподбора(заголовок: т("my_car_retake"), значок: "camera.viewfinder") { снять(false) }
                    МалаяКнопкаАвтоподбора(заголовок: т("my_car_gallery"), значок: "photo.on.rectangle") { снять(true) }
                    МалаяКнопкаАвтоподбора(заголовок: т("my_car_photo_del"), значок: "trash", опасная: true) {
                        спроситьФото = true
                    }
                }
            } else {
                ЗелёнаяКнопкаФото(заголовок: т("my_car_shoot"), значок: "camera.viewfinder") { снять(false) }
                ЗелёнаяКнопкаФото(заголовок: т("my_car_gallery"), значок: "photo.on.rectangle", контурная: true) {
                    снять(true)
                }
            }
            Label(т("my_photo_local"), systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
        }
        .карточкаМоего()
    }

    private var карточкаИмени: some View {
        VStack(alignment: .leading, spacing: 8) {
            ЗаголовокМоего(т("my_car_name"), значок: "pencil")
            TextField(т("my_car_name_ph"), text: $имя)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .accessibilityLabel(т("my_car_name"))
                .onChange(of: имя) { _, новое in
                    if новое.count > МашинаМоего.пределИмени {
                        имя = String(новое.prefix(МашинаМоего.пределИмени))
                        return
                    }
                    хранилище.переименовать(модель.id, новое)
                }
        }
        .карточкаМоего()
    }

    private func кнопки(_ машина: МашинаМоего) -> some View {
        let главная = хранилище.запись.главнаяМашина?.id == машина.id
        return VStack(alignment: .leading, spacing: 12) {
            if главная {
                Label(т("my_car_main"), systemImage: "star.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.золото)
                Text(т("my_car_main_hint"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ЗелёнаяКнопкаФото(заголовок: т("my_car_make_main"), значок: "star", контурная: true) {
                    withAnimation(ДвижениеСайта.смена) { хранилище.сделатьГлавной(машина.id) }
                    ОткликСайта.успех()
                }
            }
            МалаяКнопкаАвтоподбора(заголовок: т("my_car_remove"), значок: "trash", опасная: true) {
                спроситьУдалить = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func снять(_ галерея: Bool) {
        ОткликСайта.выбор()
        изГалереи = галерея
        съёмка = true
    }

    @ViewBuilder
    private func экранШага(_ шаг: ШагАвтоподбора) -> some View {
        switch шаг {
        case .марка:
            ВыборМаркиАвтоподбора()
        case .модель(let марка):
            ВыборМоделиАвтоподбора(марка: марка)
        case .год(let марка, let имя):
            ВыборГодаМоего(модель: модель, марка: марка, имяМодели: имя)
        case .параметрыМашины:
            ПараметрыКолёсМоего(модель: модель)
        case .параметрыТовара, .калькулятор:
            EmptyView()
        }
    }
}
