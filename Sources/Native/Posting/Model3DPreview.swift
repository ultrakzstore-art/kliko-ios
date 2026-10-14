import ARKit
import Foundation
import QuickLook
import UIKit

/**
 3D-ОБЗОР В ПОДАЧЕ — ПОСМОТРЕТЬ СОБРАННУЮ МОДЕЛЬ (продавцу, до публикации: «так её увидит покупатель»).

 USDZ с сервера качается тем же кэшем на диске, что у покупателя (КэшОбъёма, Listing3DCache.swift): своя сессия без кук
 и без URLCache, Caches/kliko-3d-v1 с общим пределом 200 МБ (старые уходят первыми), один файл не больше 150 МБ —
 загрузка обрывается сразу, как только сервер назвал длину больше (или пришло больше), а не после полной загрузки.
 Файл ложится как «.usdz» и проверяется на zip, как бы ни кончался путь адреса. Одна и та же модель после публикации
 лежит на телефоне один раз. Ушли с экрана — загрузка отменяется (ЗагрузкаМоделиОбзора3DПодачи.отменить отменяет
 задачу, отмена доходит до URLSession). Показ — системный AR Quick Look (QLPreviewController с ARQuickLookPreviewItem,
 iOS 13+): вращать, приближать и «AR» — поставить в комнату. Страница объявления у покупателя — направление «просмотр».
 */
@MainActor
final class ЗагрузкаМоделиОбзора3DПодачи {
    static let shared = ЗагрузкаМоделиОбзора3DПодачи()

    private var задача: Task<URL?, Never>? = nil

    private init() {}

    /// Файл модели на телефоне: из кэша или скачанный. nil — адрес не наш, сеть, не тот файл, великоват, отменили.
    func файл(_ адрес: URL) async -> URL? {
        guard ХодПримерочной.адрес(адрес.absoluteString) != nil else { return nil }
        задача?.cancel()
        let новая = Task { () -> URL? in
            try? await КэшОбъёма.shared.файл(адрес, прогресс: nil, расширение: "usdz")
        }
        задача = новая
        let итог = await withTaskCancellationHandler {
            await новая.value
        } onCancel: {
            новая.cancel()
        }
        if задача == новая { задача = nil }
        return итог
    }

    /// Ушли с экрана — загрузка стоит.
    func отменить() {
        задача?.cancel()
        задача = nil
    }
}

// MARK: - Показ: AR Quick Look

@MainActor
enum ПоказМоделиОбзора3DПодачи {
    /// Источник живёт, пока окно на экране (QLPreviewController держит dataSource слабо).
    private static var источник: ИсточникМоделиОбзора3DПодачи? = nil

    /// Показать модель поверх всего. false — показать некуда (что-то ещё уезжает).
    @discardableResult
    static func показать(_ файл: URL) -> Bool {
        guard let верх = ПоверхВсего.верхний() else { return false }
        let элемент = ARQuickLookPreviewItem(fileAt: файл)
        элемент.allowsContentScaling = true
        let новый = ИсточникМоделиОбзора3DПодачи(элемент: элемент)
        источник = новый
        let окно = QLPreviewController()
        окно.dataSource = новый
        окно.delegate = новый
        верх.present(окно, animated: true)
        return true
    }

    static func отпустить() {
        источник = nil
    }
}

/// Один элемент для QLPreviewController.
final class ИсточникМоделиОбзора3DПодачи: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private let элемент: QLPreviewItem

    init(элемент: QLPreviewItem) {
        self.элемент = элемент
        super.init()
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { элемент }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        Task { @MainActor in ПоказМоделиОбзора3DПодачи.отпустить() }
    }
}
