import SwiftUI
import UIKit
import AVKit
import Combine

/**
 СТУДИЯ РОЛИКОВ — окно #reel-ov сайта «Видео для Reels / TikTok» (openReelStudio из js/cabinet-reel.min.js), нативно.

 Сверху вниз, как у сайта: сцена 9 : 16 с живым превью (кадры рисует та же функция, что и запись), «Стиль: …» с
 кубиком, «Фирменный звук Kliko», подсказка, «Картинка · сразу» и «Видео». Во время записи — полоса «Рендер N %» и
 «Отменить». Готово — видео в плеере, «В галерею» (Скачать сайта) и «Поделиться», «↻ Пересоздать заново».

 Сверх сайта (владелец): выбор и порядок фото (до 5), свои название, цена и призыв концовки, громкость звука; кнопки
 Instagram Reels, Instagram Stories и TikTok; «Автопостинг в бизнес-аккаунт» (social_post, за PRO — как в окне
 «Поделиться» кабинета).

 Открывается из «Сделать видео и поделиться» окна «Поделиться» кабинета (ОкноПоделитьсяКабинета) — его зовут и «Мои
 объявления» (advShare), и подача после публикации. Отдельной кнопки «Ролик» у строк «Моих объявлений» у сайта нет.
 */
@MainActor
struct СтудияРоликов: View {
    @StateObject private var модель: МодельСтудииРоликов
    private let закрытьЛист: () -> Void

    @State private var плеер: AVPlayer? = nil
    @State private var автопостингОткрыт = false
    @FocusState private var поле: Int?

    init(данные: ДанныеОтправкиСайта, закрыть: @escaping () -> Void) {
        let м = МодельСтудииРоликов(данные: данные)
        м.закрыть = закрыть
        _модель = StateObject(wrappedValue: м)
        закрытьЛист = закрыть
    }

    private func т(_ ключ: String) -> String { ReelStudioText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ScrollView {
                VStack(spacing: 12) {
                    сцена
                    строкаСтилей
                    строкаЗвука
                    блокФото
                    блокТекстов
                    подсказка
                    действия
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // .reel-card сайта всегда тёмная, в светлой теме тоже.
        .background(КраскиСтудии.фон.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .bottom) { плашкаТоста }
        .interactiveDismissDisabled(модель.идётЗапись)
        .task { await модель.начать() }
        .onDisappear {
            модель.закрыто()
            плеер?.pause()
        }
        .onChange(of: модель.готовый) { _, новый in обновитьПлеер(новый) }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { уведомление in
            guard let элемент = уведомление.object as? AVPlayerItem, let плеер, элемент === плеер.currentItem else { return }
            плеер.seek(to: .zero)
            плеер.play()
        }
    }

    // MARK: Шапка

    private var шапка: some View {
        HStack(spacing: 8) {
            Image(systemName: "video")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(т("title"))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(КраскиСтудии.заголовок)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { закрытьЛист() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(КраскиСтудии.крестик)
                    .frame(width: 40, height: 40)
                    .background(КраскиСтудии.кнопка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
            .accessibilityLabel(т("close"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: Сцена

    private var сцена: some View {
        ZStack {
            Color.black
            if let плеер, модель.готовый != nil {
                VideoPlayer(player: плеер)
            } else {
                ПревьюСтудииРоликов(рисовальщик: модель.рисовальщик, идёт: !модель.идётЗапись && !модель.загружается)
            }
            if модель.загружается {
                VStack(spacing: 10) {
                    SiteSpinner.белый
                    Text(т("loading"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            if case .запись(let доля, let шаг) = модель.этап {
                ход(доля, шаг)
            }
        }
        .frame(width: размерСцены.width, height: размерСцены.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(т("title"))
    }

    /// .reel-stage: во всю ширину, 9 : 16, но не выше 64 % экрана (содержимое вписано, по бокам чёрное).
    private var размерСцены: CGSize {
        let экран = UIScreen.main.bounds.size
        let ширина = max(200, min(экран.width, 520) - 28)
        return CGSize(width: ширина, height: min(ширина * 16 / 9, экран.height * 0.64))
    }

    /// #reel-prog сайта: полоса и «Рендер N %» поверх сцены, под ней «Отменить».
    private func ход(_ доля: Double, _ шаг: ЭтапЗаписиРолика) -> some View {
        let подпись: String
        switch шаг {
        case .кадры: подпись = т("prep")
        case .рендер: подпись = String(format: т("render"), Int((доля * 100).rounded()))
        case .сборка: подпись = т("mux")
        }
        return ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                // .reel-bar: 60 % ширины, 6 пт, белая 0.18 и зелёная заливка.
                GeometryReader { гео in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.18))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(LinearGradient(colors: [КраскиСтудии.ходНачало, КраскиСтудии.ходКонец],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, гео.size.width * CGFloat(min(1, max(0, доля)))))
                    }
                }
                .frame(width: размерСцены.width * 0.6, height: 6)
                .animation(ДвижениеСайта.прогресс, value: доля)
                Text(подпись)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(КраскиСтудии.крестик)
                    .monospacedDigit()
                Button { модель.отменить() } label: {
                    Text(т("cancel"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 36)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Стиль и звук

    /// .reel-style сайта («Стиль: Изумруд 🎲») — здесь все пять стилей видны сразу, кубик — случайный другой.
    private var строкаСтилей: some View {
        VStack(alignment: .leading, spacing: 8) {
            заголовокБлока(т("style"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { модель.другойСтиль() } label: {
                        Image(systemName: "dice")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(КраскиСтудии.текстФишки)
                            .frame(width: 40, height: 40)
                            .background(КраскиСтудии.фишка, in: Circle())
                            .overlay(Circle().stroke(КраскиСтудии.кромкаФишки, lineWidth: 1))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
                    .accessibilityLabel(т("style_other"))
                    ForEach(Array(СтильРолика.все.enumerated()), id: \.element.id) { пара in
                        фишкаСтиля(пара.offset, пара.element)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(модель.идётЗапись)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func фишкаСтиля(_ номер: Int, _ стиль: СтильРолика) -> some View {
        let выбран = модель.номерСтиля == номер
        return Button { модель.выбратьСтиль(номер) } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(uiColor: КраскиРолика.цвет(стиль.фон.0)),
                                                      Color(uiColor: КраскиРолика.цвет(стиль.фон.1))],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle()
                        .fill(Color(uiColor: КраскиРолика.цвет(стиль.акцент)))
                        .frame(width: 8, height: 8)
                }
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                Text(т(стиль.ключИмени))
                    .font(.system(size: 13, weight: выбран ? .heavy : .semibold))
                    .foregroundStyle(выбран ? Color.white : КраскиСтудии.текстФишки)
                    .lineLimit(1)
            }
            .padding(.leading, 9)
            .padding(.trailing, 14)
            .frame(height: 40)
            .background(выбран ? Theme.акцент.opacity(0.14) : КраскиСтудии.фишка, in: Capsule())
            .overlay(Capsule().stroke(выбран ? Theme.акцент : КраскиСтудии.кромкаФишки, lineWidth: выбран ? 1.6 : 1))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .accessibilityAddTraits(выбран ? [.isSelected] : [])
        .animation(ДвижениеСайта.выбор, value: выбран)
    }

    /// .reel-snd сайта и громкость.
    private var строкаЗвука: some View {
        VStack(spacing: 6) {
            Toggle(isOn: $модель.звук) {
                Label(т("sound"), systemImage: модель.звук ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(КраскиСтудии.звук)
            }
            .tint(Theme.акцент)
            if модель.звук {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                    Slider(value: $модель.громкость, in: 0.1...1)
                        .tint(Theme.акцент)
                        .accessibilityLabel(т("volume"))
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(КраскиСтудии.фишка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .stroke(КраскиСтудии.кромкаФишки, lineWidth: 1)
        )
        .disabled(модель.идётЗапись)
        .animation(ДвижениеСайта.смена, value: модель.звук)
    }

    // MARK: Фото

    private var блокФото: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                заголовокБлока(т("photos"))
                Spacer(minLength: 0)
                Text("\(модель.включено)/\(МодельСтудииРоликов.наибольшеФото)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .monospacedDigit()
            }
            if модель.фото.isEmpty && !модель.загружается {
                Text(т("photos_none"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(модель.фото.enumerated()), id: \.element.id) { пара in
                            ячейкаФото(пара.offset, пара.element)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text(т("photos_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(модель.идётЗапись)
    }

    private func ячейкаФото(_ номер: Int, _ ф: ФотоРолика) -> some View {
        let место = модель.фото.prefix(номер + 1).filter { $0.включено }.count
        return VStack(spacing: 6) {
            Button { модель.переключить(ф.id) } label: {
                ZStack(alignment: .topLeading) {
                    Group {
                        if let картинка = ф.картинка {
                            Image(uiImage: картинка).resizable().scaledToFill()
                        } else if ф.загружено {
                            Theme.поверхность2.overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Theme.текстВторой)
                            )
                        } else {
                            Theme.поверхность2.overlay(SiteSpinner.мелкий)
                        }
                    }
                    .frame(width: 68, height: 104)
                    .clipped()
                    .opacity(ф.включено ? 1 : 0.35)
                    Text(ф.включено ? "\(место)" : "–")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(ф.включено ? Color.white : Theme.текстВторой)
                        .frame(width: 22, height: 22)
                        .background(ф.включено ? Theme.акцент : Theme.поверхность, in: Circle())
                        .padding(5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ф.включено ? Theme.акцент : Theme.линия, lineWidth: ф.включено ? 2 : 1)
                )
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
            .accessibilityLabel(String(format: т("photo_n"), номер + 1))
            .accessibilityValue(ф.включено ? т("on") : т("off"))
            HStack(spacing: 4) {
                кнопкаСдвига("chevron.backward", т("move_left"), доступна: номер > 0) {
                    модель.сдвинуть(ф.id, на: -1)
                }
                кнопкаСдвига("chevron.forward", т("move_right"), доступна: номер < модель.фото.count - 1) {
                    модель.сдвинуть(ф.id, на: 1)
                }
            }
        }
    }

    private func кнопкаСдвига(_ значок: String, _ подпись: String, доступна: Bool,
                              действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(доступна ? Theme.текст : Theme.текстВторой.opacity(0.4))
                .frame(width: 32, height: 26)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
        .disabled(!доступна)
        .accessibilityLabel(подпись)
    }

    // MARK: Тексты

    private var блокТекстов: some View {
        VStack(alignment: .leading, spacing: 8) {
            заголовокБлока(т("texts"))
            полеТекста(т("f_title"), $модель.название, номер: 0, строк: 3)
            полеТекста(т("f_price"), $модель.цена, номер: 1, строк: 1)
            полеТекста(т("f_cta"), $модель.призыв, номер: 2, строк: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(модель.идётЗапись)
    }

    private func полеТекста(_ подпись: String, _ текст: Binding<String>, номер: Int, строк: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(подпись)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            TextField(подпись, text: текст, axis: .vertical)
                .lineLimit(1...строк)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .focused($поле, equals: номер)
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .stroke(поле == номер ? Theme.акцент : Theme.линия, lineWidth: поле == номер ? 1.5 : 1)
                )
        }
    }

    // MARK: Подсказка и действия

    /// #reel-hint сайта.
    private var подсказка: some View {
        let текст: String
        switch модель.этап {
        case .превью, .запись:
            текст = т("hint")
        case .готово(let ролик):
            let звук = модель.звук ? (ролик.соЗвуком ? т("ready_snd") : т("ready_nosnd")) : ""
            текст = звук.isEmpty ? т("ready") : "\(т("ready")) \(звук)"
        case .сбой:
            текст = т("fail")
        }
        return Text(текст)
            .font(.system(size: 12))
            .lineSpacing(3)
            .foregroundStyle(модель.этап == .сбой ? Theme.цвет(0xB42318, 0xF97066) : КраскиСтудии.подсказка)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var действия: some View {
        if модель.готовый != nil {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    кнопка(т("save"), значок: "arrow.down.to.line", вид: .вторая) { модель.вГалерею() }
                    кнопка(т("share"), значок: "square.and.arrow.up", вид: .поделиться) { модель.поделиться() }
                }
                соцсети
                Button { модель.сделатьВидео() } label: {
                    Text(т("remake"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскиСтудии.заново)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                автопостинг
            }
        } else {
            HStack(spacing: 10) {
                Button { модель.картинка() } label: {
                    HStack(spacing: 6) {
                        if модель.картинкаГотовится {
                            SiteSpinner.мелкий
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text(т("make_image"))
                            .font(.system(size: 14, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(т("tag_now"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(КраскиСтудии.ходНачалоТёмное, in: Capsule())
                            .fixedSize()
                    }
                    .foregroundStyle(КраскиСтудии.текстФишки)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(КраскиСтудии.кнопка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .disabled(модель.идётЗапись || модель.загружается)
                кнопка(т("make_video"), значок: "video", вид: .главная) { модель.сделатьВидео() }
                    .disabled(модель.идётЗапись || модель.загружается)
                    .opacity(модель.идётЗапись ? 0.6 : 1)
            }
        }
    }

    /// .reel-btn: cta — зелёный градиент, sec — #232b26, share — градиент Instagram; 14 жирный, отступ 14, скругление 14.
    private enum ВидКнопкиСтудии { case главная, вторая, поделиться }

    private func кнопка(_ подпись: String, значок: String, вид: ВидКнопкиСтудии,
                        действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 7) {
                Image(systemName: значок)
                    .font(.system(size: 14, weight: .semibold))
                Text(подпись)
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(вид == .вторая ? КраскиСтудии.текстФишки : Color.white)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background {
                let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                switch вид {
                case .главная:
                    форма.fill(LinearGradient(colors: [КраскиСтудии.ходНачалоТёмное, КраскиСтудии.ходНачало],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                case .вторая:
                    форма.fill(КраскиСтудии.кнопка)
                case .поделиться:
                    форма.fill(LinearGradient(stops: [
                        .init(color: Color(uiColor: Theme.hex(0xF9CE34)), location: 0),
                        .init(color: Color(uiColor: Theme.hex(0xEE2A7B)), location: 0.42),
                        .init(color: Color(uiColor: Theme.hex(0x6228D7)), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    /// Instagram Reels, Instagram Stories, TikTok.
    private var соцсети: some View {
        HStack(spacing: 8) {
            кнопкаСети(т("reels"), значок: "play.rectangle.on.rectangle", instagram: true) { модель.instagramReels() }
            кнопкаСети(т("stories"), значок: "circle.dashed", instagram: true) { модель.instagramStories() }
            кнопкаСети(т("tiktok"), значок: "music.note", instagram: false) { модель.tikTok() }
        }
    }

    private func кнопкаСети(_ подпись: String, значок: String, instagram: Bool,
                            действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            VStack(spacing: 5) {
                Image(systemName: значок)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background {
                        if instagram {
                            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ПоделитьсяСайта.цветаInstagram)
                        } else {
                            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black)
                        }
                    }
                Text(подпись)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
    }

    // MARK: Автопостинг

    /// «Автопостинг в бизнес-аккаунт ⌄» окна «Поделиться» кабинета: Instagram и TikTok по social_status, за PRO.
    private var автопостинг: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(ДвижениеСайта.смена) { автопостингОткрыт.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(т("autopost"))
                        .font(.system(size: 13, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(автопостингОткрыт ? 180 : 0))
                }
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            if автопостингОткрыт {
                Group {
                    if let сети = модель.соцсети {
                        VStack(spacing: 8) {
                            строкаАвтопостинга("instagram", "Instagram", сети["instagram"] ?? СоцсетьРолика())
                            строкаАвтопостинга("tiktok", "TikTok", сети["tiktok"] ?? СоцсетьРолика())
                        }
                    } else {
                        HStack(spacing: 8) {
                            SiteSpinner.мелкий
                            Text(т("ap_loading"))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .transition(.opacity)
                .task { await модель.загрузитьСоцсети() }
            }
        }
    }

    private func строкаАвтопостинга(_ ключ: String, _ имя: String, _ с: СоцсетьРолика) -> some View {
        let готово = модель.опубликованоВ.contains(ключ)
        let идёт = модель.публикуется == ключ
        let заголовок: String
        let пояснение: String
        if !с.включено {
            заголовок = имя
            пояснение = т("soon")
        } else if готово {
            заголовок = т("posted")
            пояснение = с.имя.isEmpty ? "" : "@\(с.имя)"
        } else if идёт {
            заголовок = т("posting")
            пояснение = ""
        } else if с.подключено {
            заголовок = String(format: т("post_to"), имя)
            пояснение = с.имя.isEmpty ? "" : "@\(с.имя)"
        } else {
            заголовок = String(format: т("connect"), имя)
            пояснение = т("connect_sub")
        }
        return Button { модель.нажатаСоцсеть(ключ, имя) } label: {
            HStack(spacing: 10) {
                Image(systemName: ключ == "instagram" ? "camera" : "music.note")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background {
                        if ключ == "instagram" {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ПоделитьсяСайта.цветаInstagram)
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
                        }
                    }
                    .opacity(с.включено ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(с.включено ? Theme.текст : Theme.текстВторой)
                    if !пояснение.isEmpty {
                        Text(пояснение)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                Spacer(minLength: 0)
                if идёт {
                    SiteSpinner.мелкий
                } else if готово {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!с.включено || готово || модель.публикуется != nil)
    }

    // MARK: Общее

    private func заголовокБлока(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.текст)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var плашкаТоста: some View {
        if let тост = модель.тост {
            Text(тост)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: Theme.hex(0x12271C, 0.94)), in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func обновитьПлеер(_ ролик: ГотовыйРолик?) {
        плеер?.pause()
        guard let ролик else {
            плеер = nil
            return
        }
        let новый = AVPlayer(url: ролик.файл)
        плеер = новый
        новый.play()
    }
}

// MARK: - Краски

/// Краски окна студии (.reel-card сайта): одинаковые в светлой и тёмной теме.
private enum КраскиСтудии {
    static let фон = Color(uiColor: Theme.hex(0x0F1512))
    static let заголовок = Color(uiColor: Theme.hex(0xF1F5F2))
    static let кнопка = Color(uiColor: Theme.hex(0x232B26))
    static let крестик = Color(uiColor: Theme.hex(0xCFE0D6))
    static let подсказка = Color(uiColor: Theme.hex(0x8EA699))
    static let звук = Color(uiColor: Theme.hex(0x9FB0A6))
    static let фишка = Color(uiColor: Theme.hex(0x1B241F))
    static let кромкаФишки = Color(uiColor: Theme.hex(0x2B3630))
    static let текстФишки = Color(uiColor: Theme.hex(0xDBE7E0))
    static let заново = Color(uiColor: Theme.hex(0x7F958A))
    static let ходНачалоТёмное = Color(uiColor: Theme.hex(0x0F7A44))
    static let ходНачало = Color(uiColor: Theme.hex(0x1D9E5E))
    static let ходКонец = Color(uiColor: Theme.hex(0x37D07F))
}

// MARK: - Превью

/// Живое превью: кадр 540 × 960 (как холст #reel-canvas сайта) 30 раз в секунду по кругу.
private struct ПревьюСтудииРоликов: View {
    let рисовальщик: РисовальщикРолика?
    let идёт: Bool
    @State private var начало = Date()

    init(рисовальщик: РисовальщикРолика?, идёт: Bool) {
        self.рисовальщик = рисовальщик
        self.идёт = идёт
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !идёт)) { контекст in
            let картинка = кадр(контекст.date)
            if let картинка {
                Image(uiImage: картинка)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
            } else {
                Color.black
            }
        }
        .accessibilityHidden(true)
    }

    private func кадр(_ сейчас: Date) -> UIImage? {
        guard let рисовальщик else { return nil }
        let всего = max(0.1, рисовальщик.ход.всего)
        let t = max(0, сейчас.timeIntervalSince(начало)).truncatingRemainder(dividingBy: всего)
        return рисовальщик.кадр(t, масштаб: 0.5)
    }
}

// MARK: - Показ

extension СтудияРоликов {
    /// Студия поверх верхнего экрана (над окном «Поделиться»), лист на всю высоту.
    @MainActor
    static func показать(_ данные: ДанныеОтправкиСайта) {
        guard let верх = ПоделитьсяСайта.верхнийЭкран() else { return }
        let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let экран = СтудияРоликов(данные: данные, закрыть: { [weak хост] in хост?.dismiss(animated: true) })
        хост.rootView = AnyView(экран)
        хост.view.backgroundColor = Theme.hex(0x0F1512)
        хост.overrideUserInterfaceStyle = .dark
        хост.modalPresentationStyle = .pageSheet
        if let лист = хост.sheetPresentationController {
            лист.detents = [.large()]
            лист.prefersGrabberVisible = true
            лист.preferredCornerRadius = 22
        }
        верх.present(хост, animated: true)
    }
}
