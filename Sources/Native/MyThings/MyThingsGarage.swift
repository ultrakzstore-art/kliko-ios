import SwiftUI
import UIKit

/**
 «МОЁ» — «МОЙ ГАРАЖ» (владелец 14.10.2026: «моя машина — туда можно будет примерить диски (чел фоткает по шаблону свою
 тачку)»).

 До 5 машин карточками: фото сбоку 16:9 (миниатюра), звезда «Главная» (перелетает между карточками), название и
 фишки PCD · ET · DIA · R · шина, пометка «из справочника / введено вами». Нет фото — силуэт машины пунктиром и кнопка
 «Снять по шаблону» прямо на карточке. Пусто — силуэт «дышит» один раз и «Добавить машину». С главной машиной
 сверяются шины и диски в «Подойдут ли?» (ГаражАвтоподбора берёт её отсюда).

 Редактор машины (MyThingsCarEditor.swift) — лист в своей навигации ([ШагАвтоподбора]): марка → модель (пикеры «Подойдут ли?») → год (свой,
 ВыборГодаМоего) → справочник посадки; не нашёлся — параметры колёс вручную (ПараметрыКолёсМоего). Ниже — фото сбоку с
 кольцами колёс (тащатся пальцем), своё название, «Сделать главной», «Удалить машину». Сохраняется само на каждое
 изменение; «Готово» закрывает. Закрыли, ничего не указав, — пустая машина в гараже не остаётся.

 Пачка 83 (§16): под карточкой — «Ищу шины …» (сохранённый поиск со стандартом) и «Продать ▾» (шины или диски машины —
 мастер подачи уже заполнен). Своё название машины никуда не уходит.
 */
struct ЭкранГаражаМоего: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @Namespace private var звезда
    @State private var редактор: ЦельМашиныМоего? = nil
    @State private var съёмка: ЦельМашиныМоего? = nil
    @State private var удалить: ЦельМашиныМоего? = nil
    @State private var показ = 0

    init() {}

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    private var тихо: Bool { безДвижения || ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий }

    var body: some View {
        let машины = хранилище.запись.машины
        ScrollView {
            VStack(spacing: 14) {
                if машины.isEmpty {
                    пусто
                        .transition(.opacity)
                } else {
                    ForEach(машины) { машина in
                        VStack(alignment: .leading, spacing: 8) {
                            карточка(машина)
                            действия(машина)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    низ(машины.count)
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.вставкаСписка, value: машины.map(\.id))
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(т("my_garage"))
        .sheet(item: $редактор, onDismiss: { убратьПустые() }) { цель in
            РедакторМашиныМоего(id: цель.id)
        }
        .fullScreenCover(item: $съёмка) { цель in
            КамераШаблонаМоего(шаблон: .машинаСбоку) { снимок in
                await МоёХранилище.shared.сохранитьФотоМашины(цель.id, готовое: снимок.готовое, колёса: снимок.колёса,
                                                              люди: снимок.люди, шаблон: снимок.шаблон)
            }
        }
        .confirmationDialog(т("my_car_remove_q"), isPresented: спроситьУдалить, titleVisibility: .visible) {
            Button(т("my_delete"), role: .destructive) {
                if let цель = удалить { хранилище.удалитьМашину(цель.id) }
                удалить = nil
            }
            Button(т("my_cancel"), role: .cancel) { удалить = nil }
        }
        .onAppear {
            хранилище.подготовить()
            показ += 1
        }
    }

    private var спроситьУдалить: Binding<Bool> {
        Binding(get: { удалить != nil }, set: { if !$0 { удалить = nil } })
    }

    /// Карточка — кнопка редактора; у машины без фото поверх места фото — «Снять по шаблону» (своя кнопка, рядом,
    /// а не внутри карточки). Долгое нажатие — «Сделать главной» и «Удалить машину».
    private func карточка(_ машина: МашинаМоего) -> some View {
        let главная = машина.id == хранилище.запись.главнаяМашина?.id
        return Button {
            ОткликСайта.выбор()
            редактор = ЦельМашиныМоего(id: машина.id)
        } label: {
            КарточкаМашиныМоего(машина: машина, главная: главная, звезда: звезда)
        }
        .buttonStyle(НажатиеСайта())
        .overlay(alignment: .top) {
            if машина.фото == nil {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .padding(10)
                    .overlay(alignment: .bottom) {
                        кнопкаСъёмки(машина.id)
                            .padding(.bottom, 12)
                    }
            }
        }
        .contextMenu {
            if !главная {
                Button {
                    сделатьГлавной(машина.id)
                } label: {
                    Label(т("my_car_make_main"), systemImage: "star")
                }
            }
            Button(role: .destructive) {
                удалить = ЦельМашиныМоего(id: машина.id)
            } label: {
                Label(т("my_car_remove"), systemImage: "trash")
            }
        }
    }

    /**
     Под карточкой машины (пачка 83): «Ищу шины 205/55 R16» (сохранённый поиск со стандартом, MyThingsWanted.swift) и
     «Продать» — меню «Шины 205/55 R16» / «Диски R16 5×114.3» (мастер подачи уже заполнен, MyThingsSell.swift). Нет
     размеров — ряда нет.
     */
    @ViewBuilder
    private func действия(_ машина: МашинаМоего) -> some View {
        let ищу: ЗапросИщуМоего? = ИщуМоего.машина(машина)
        let шины: ЗаготовкаПодачи? = ПродатьСвоёМоего.шины(машина)
        let диски: ЗаготовкаПодачи? = ПродатьСвоёМоего.диски(машина)
        let естьПродажа: Bool = шины != nil || диски != nil
        if ищу != nil || естьПродажа {
            ПотокЧипов(зазор: 8) {
                if let ищу {
                    КнопкаИщуМоего(ищу)
                }
                if естьПродажа {
                    менюПродать(машина, шины: шины, диски: диски)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// «Продать ▾»: шины и диски машины комплектом — мастер подачи с готовыми полями.
    private func менюПродать(_ машина: МашинаМоего, шины: ЗаготовкаПодачи?, диски: ЗаготовкаПодачи?) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        let размерШин: String = машина.посадка?.шины.first?.подпись ?? ""
        let подписьДисков: String = ПродатьСвоёМоего.подписьДисков(машина) ?? ""
        return Menu {
            if let шины {
                Button {
                    продать(шины)
                } label: {
                    Label(ПродатьМоёText.ф("msl_sell_tyres", размерШин), systemImage: "circle.circle")
                }
            }
            if let диски {
                Button {
                    продать(диски)
                } label: {
                    Label(ПродатьМоёText.ф("msl_sell_rims", подписьДисков), systemImage: "gearshape")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(ПродатьМоёText.т("msl_sell"))
                    .font(.subheadline.weight(.bold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.акцент)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.оттенокАкцента, in: форма)
            .contentShape(форма)
        }
        .accessibilityLabel(ПродатьМоёText.т("msl_sell"))
        .accessibilityHint(ПродатьМоёText.т("msl_sell_hint"))
    }

    private func продать(_ заготовка: ЗаготовкаПодачи) {
        ОткликСайта.выбор()
        ПереходыГардероба.продать(заготовка)
    }

    private func кнопкаСъёмки(_ id: UUID) -> some View {
        Button {
            ОткликСайта.выбор()
            съёмка = ЦельМашиныМоего(id: id)
        } label: {
            Label(т("my_car_shoot"), systemImage: "camera.viewfinder")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.зелёный2, in: Capsule())
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
    }

    /// Пусто: силуэт машины пунктиром мягко «вдыхает» один раз, подпись и «Добавить машину».
    private var пусто: some View {
        VStack(spacing: 18) {
            СилуэтМашиныПримерочной()
                .stroke(Theme.акцент.opacity(0.75),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [7, 6]))
                .aspectRatio(СилуэтМашиныПримерочной.пропорция, contentMode: .fit)
                .frame(maxWidth: 260)
                .phaseAnimator(тихо ? [1.0] : [1.0, 1.04, 1.0], trigger: показ) { вид, масштаб in
                    вид.scaleEffect(масштаб)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
                .accessibilityHidden(true)
            Text(т("my_garage_empty"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ЗелёнаяКнопкаФото(заголовок: т("my_car_add"), значок: "plus") { добавить() }
        }
        .frame(maxWidth: .infinity)
        .карточкаМоего(поля: 24)
    }

    /// «Добавить машину» (до 5) и подпись о главной машине.
    private func низ(_ сколько: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if сколько < ЗаписьМоего.пределМашин {
                ЗелёнаяКнопкаФото(заголовок: т("my_car_add"), значок: "plus", контурная: true) { добавить() }
            } else {
                Text(т("my_car_limit"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            Label {
                Text(т("my_car_main_hint"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.золото)
            }
            .font(.footnote)
            .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func добавить() {
        guard let id = хранилище.добавитьМашину() else {
            ОткликСайта.предупреждение()
            return
        }
        ОткликСайта.выбор()
        редактор = ЦельМашиныМоего(id: id)
    }

    private func сделатьГлавной(_ id: UUID) {
        withAnimation(ДвижениеСайта.мягко(.spring(response: 0.45, dampingFraction: 0.8))) {
            хранилище.сделатьГлавной(id)
        }
        ОткликСайта.успех()
    }

    private func убратьПустые() {
        for машина in хранилище.запись.машины { хранилище.убратьПустую(машина.id) }
    }
}

/// Цель листа и камеры гаража — машина по номеру.
struct ЦельМашиныМоего: Identifiable, Hashable {
    let id: UUID
}

// MARK: - Карточка машины

/// Фото 16:9 (миниатюра) или силуэт, звезда «Главная», название, фишки параметров и откуда они.
struct КарточкаМашиныМоего: View {
    let машина: МашинаМоего
    let главная: Bool
    let звезда: Namespace.ID

    init(машина: МашинаМоего, главная: Bool, звезда: Namespace.ID) {
        self.машина = машина
        self.главная = главная
        self.звезда = звезда
    }

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            фото
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(машина.заголовок)
                        .font(.headline)
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if главная {
                        бейдж
                            .matchedGeometryEffect(id: "main", in: звезда)
                    }
                }
                if машина.имя.isEmpty == false, let авто = машина.авто {
                    Text(авто.подпись)
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                }
                фишки
                источник
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: форма)
        .теньКарточкиСайта(радиус: Theme.Радиус.md)
        .contentShape(форма)
        .accessibilityElement(children: .combine)
        .accessibilityHint(т("my_car_edit_hint"))
    }

    private var фото: some View {
        Theme.поверхность2
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let ф = машина.фото {
                    ФотоМоегоВид(имя: ф.мини)
                } else {
                    СилуэтМашиныПримерочной()
                        .stroke(Theme.акцент.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                        .aspectRatio(СилуэтМашиныПримерочной.пропорция, contentMode: .fit)
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                        .padding(.bottom, 52)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
    }

    private var бейдж: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption2.weight(.bold))
            Text(т("my_car_main"))
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(LinearGradient(colors: [Theme.топНачало, Theme.топКонец], startPoint: .topLeading,
                                   endPoint: .bottomTrailing), in: Capsule())
    }

    @ViewBuilder
    private var фишки: some View {
        if !машина.чипы.isEmpty {
            ПотокЧипов(зазор: 6) {
                ForEach(машина.чипы, id: \.self) { текст in
                    Text(текст)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.акцент)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.оттенокАкцента, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var источник: some View {
        if let п = машина.посадка {
            Label(АвтоподборText.т(п.свои ? "af_src_own" : "af_src_ref"),
                  systemImage: п.свои ? "person.fill" : "books.vertical.fill")
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
        } else {
            Label(т(машина.авто == nil ? "my_next_car" : "my_next_params"), systemImage: "plus.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.акцент)
        }
    }
}
