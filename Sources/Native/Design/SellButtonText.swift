import Foundation

/**
 Тексты большой кнопки «Продать» нижней панели (SellButton.swift, владелец 14.10.2026) на языке телефона (kk/ru/en/ar),
 как РовныеКарточкиText. Подпись самой кнопки — прежняя DesignText «sell»; здесь — подсказка VoiceOver: кнопка с «+»
 создаёт новое объявление.
 */
enum КнопкаПродатьText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "hint": "Создать новое объявление"
    ]

    private static let kk: [String: String] = [
        "hint": "Жаңа хабарландыру жасау"
    ]

    private static let en: [String: String] = [
        "hint": "Create a new listing"
    ]

    private static let ar: [String: String] = [
        "hint": "إنشاء إعلان جديد"
    ]
}
