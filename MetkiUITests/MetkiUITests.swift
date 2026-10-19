import XCTest

final class MetkiUITests: XCTestCase {
    func testEnglishLocalizationPreservesUserContent() {
        let app = launch(seed: true, language: "en", locale: "ru_RU")
        XCTAssertTrue(app.staticTexts["Metki"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Read tag"].exists)
        XCTAssertFalse(app.buttons["Read tag"].isEnabled)
        attach(named: "read-en")

        app.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Work"].exists)
        XCTAssertTrue(app.buttons["Things"].exists)
        XCTAssertTrue(app.staticTexts["Кухня"].exists)
        app.staticTexts["Кухня"].tap()
        let name = input(app, "Name")
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "Кухня")
        XCTAssertTrue(app.staticTexts["ISO 14443 · 7 bytes"].exists)
        XCTAssertTrue(app.buttons["Item photo"].exists)
        attach(named: "card-en")

        app.buttons["Write"].tap()
        app.buttons["Add record"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 3))
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Enter text."].waitForExistence(timeout: 3))
        let text = input(app, "Text")
        text.tap()
        text.typeText("Hello NFC!!")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["31 bytes"].waitForExistence(timeout: 3))

        app.buttons["Add record"].tap()
        let secondText = input(app, "Text")
        secondText.tap()
        secondText.typeText("Мой текст")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Мой текст"].waitForExistence(timeout: 3))
        attach(named: "write-en")
    }

    func testReadWriteAndLibrary() {
        let app = launch()

        XCTAssertTrue(app.staticTexts["Метки"].waitForExistence(timeout: 5))
        let nfcBanner = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "NFC недоступен")).firstMatch
        let nfcShown = nfcBanner.waitForExistence(timeout: 5)
        XCTAssertTrue(nfcShown)
        XCTAssertTrue(app.buttons["Считать метку"].exists)
        XCTAssertFalse(app.buttons["Считать метку"].isEnabled)
        attach(named: "read")

        app.buttons["Запись"].tap()
        XCTAssertTrue(app.staticTexts["Запись"].waitForExistence(timeout: 3))
        app.buttons["Добавить запись"].tap()

        let textInput = app.textViews["Текст"]
        let textField = app.textFields["Текст"]
        if textInput.waitForExistence(timeout: 3) {
            textInput.tap()
            textInput.typeText("Привет, метка")
        } else {
            XCTAssertTrue(textField.waitForExistence(timeout: 2))
            textField.tap()
            textField.typeText("Привет, метка")
        }
        if app.buttons["Готово"].exists {
            app.buttons["Готово"].tap()
        }
        app.buttons["Добавить"].tap()

        XCTAssertTrue(app.staticTexts["Привет, метка"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Записать на метку"].exists)
        XCTAssertFalse(app.buttons["Записать на метку"].isEnabled)
        XCTAssertFalse(app.buttons["Очистить метку"].isEnabled)
        attach(named: "write")

        app.buttons["Библиотека"].tap()
        XCTAssertTrue(app.staticTexts["Пока пусто"].waitForExistence(timeout: 3))
        attach(named: "library")

        app.buttons["Чтение"].tap()
        XCTAssertTrue(app.staticTexts["Метки"].waitForExistence(timeout: 3))
    }

    func testComposerValidationAndDrafts() {
        let app = launch()
        app.buttons["Запись"].tap()
        XCTAssertTrue(app.buttons["Добавить запись"].waitForExistence(timeout: 5))
        app.buttons["Добавить запись"].tap()
        XCTAssertTrue(app.buttons["Добавить"].waitForExistence(timeout: 3))
        app.buttons["Добавить"].tap()
        let validation = app.staticTexts["Введите текст."].waitForExistence(timeout: 3)
        XCTAssertTrue(validation)

        let text = input(app, "Текст")
        text.tap()
        text.typeText("Привет, метка")
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["Привет, метка"].waitForExistence(timeout: 3))

        app.buttons["Добавить запись"].tap()
        XCTAssertTrue(app.buttons["Ссылка"].waitForExistence(timeout: 3))
        app.buttons["Ссылка"].tap()
        let address = input(app, "Адрес")
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        address.tap()
        address.typeText("example.com")
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["https://example.com"].waitForExistence(timeout: 3))

        app.buttons["Добавить запись"].tap()
        let wifi = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Wi")).firstMatch
        XCTAssertTrue(wifi.waitForExistence(timeout: 3))
        wifi.tap()
        let network = input(app, "Имя сети")
        XCTAssertTrue(network.waitForExistence(timeout: 3))
        network.tap()
        network.typeText("Office")
        let password = input(app, "Пароль")
        password.tap()
        password.typeText("secret")
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["Office"].waitForExistence(timeout: 3))
        attach(named: "drafts")

        app.buttons["Библиотека"].tap()
        app.buttons["Запись"].tap()
        let kept = app.staticTexts["Привет, метка"].waitForExistence(timeout: 3)
            && app.staticTexts["https://example.com"].exists
            && app.staticTexts["Office"].exists
        XCTAssertTrue(kept)

        while app.buttons["Убрать запись"].firstMatch.exists {
            app.buttons["Убрать запись"].firstMatch.tap()
        }
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Добавьте текст")).firstMatch
                .waitForExistence(timeout: 3)
        )
    }

    func testLibraryFiltersSearchAndDetail() {
        let app = launch(seed: true)
        app.buttons["Библиотека"].tap()
        XCTAssertTrue(app.staticTexts["Офис"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Импорт"].exists)
        XCTAssertTrue(app.buttons["Экспорт"].exists)
        XCTAssertTrue(app.staticTexts["Кухня"].exists)
        XCTAssertTrue(app.staticTexts["Ключи"].exists)

        app.buttons["Дом"].tap()
        XCTAssertTrue(app.staticTexts["Кухня"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Офис"].exists)

        app.buttons["Все"].tap()
        let search = app.searchFields["Имя, номер или текст"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["Ничего не найдено"].waitForExistence(timeout: 3))
        if search.buttons["Clear text"].exists {
            search.buttons["Clear text"].tap()
        } else if search.buttons["Очистить текст"].exists {
            search.buttons["Очистить текст"].tap()
        } else {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        }
        XCTAssertTrue(app.staticTexts["Кухня"].waitForExistence(timeout: 3))

        app.buttons["Сначала новые"].tap()
        app.buttons["По имени"].tap()
        let cells = app.cells
        if cells.count >= 3 {
            XCTAssertTrue(cells.element(boundBy: 0).staticTexts["Офис"].exists)
            XCTAssertTrue(cells.element(boundBy: 1).staticTexts["Ключи"].exists)
            XCTAssertTrue(cells.element(boundBy: 2).staticTexts["Кухня"].exists)
        }
        attach(named: "library-filled")

        app.staticTexts["Кухня"].tap()
        let note = input(app, "Заметка")
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        let noteReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Холодильник"), object: note)
        XCTAssertEqual(XCTWaiter.wait(for: [noteReady], timeout: 3), .completed)
        XCTAssertTrue(app.staticTexts["https://kitchen.example"].exists)
        app.buttons["Закрепить"].tap()
        XCTAssertTrue(app.buttons["Открепить"].waitForExistence(timeout: 3))
        app.buttons["Вещи"].tap()

        let name = input(app, "Имя")
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let existing = (name.value as? String) ?? ""
        if !existing.isEmpty {
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        name.typeText("Плита")
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
        let back = app.navigationBars.buttons["Библиотека"]
        if back.waitForExistence(timeout: 2) {
            back.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.staticTexts["Плита"].waitForExistence(timeout: 3))
        attach(named: "library-renamed")
    }

    func testDeleteUndoAndCopyToWrite() {
        let app = launch(seed: true)
        app.buttons["Библиотека"].tap()
        XCTAssertTrue(app.staticTexts["Ключи"].waitForExistence(timeout: 5))
        app.staticTexts["Ключи"].tap()
        let remove = app.buttons["Удалить из библиотеки"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        reveal(remove, in: app)
        remove.tap()
        app.buttons["Удалить"].tap()
        XCTAssertTrue(app.staticTexts["Удалена «Ключи»"].waitForExistence(timeout: 3))
        app.buttons["Вернуть"].tap()
        XCTAssertTrue(app.staticTexts["Ключи"].waitForExistence(timeout: 3))

        app.staticTexts["Кухня"].tap()
        let rewrite = app.buttons["Записать на другую метку"]
        XCTAssertTrue(rewrite.waitForExistence(timeout: 3))
        reveal(rewrite, in: app)
        rewrite.tap()
        XCTAssertTrue(app.staticTexts["https://kitchen.example"].waitForExistence(timeout: 3))
        app.buttons["Библиотека"].tap()
        app.buttons["Запись"].tap()
        XCTAssertTrue(app.staticTexts["https://kitchen.example"].waitForExistence(timeout: 3))
        attach(named: "rewrite")
    }

    func testLastScanSurvivesTabSwitch() {
        let app = launch(scan: true)
        XCTAssertTrue(app.staticTexts["Последнее чтение"].waitForExistence(timeout: 5))
        app.buttons["Библиотека"].tap()
        app.buttons["Чтение"].tap()
        XCTAssertTrue(app.staticTexts["Последнее чтение"].waitForExistence(timeout: 3))
    }

    func testDarkWriteScreen() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        let app = launch()
        app.buttons["Запись"].tap()
        XCTAssertTrue(app.buttons["Добавить запись"].waitForExistence(timeout: 5))
        attach(named: "write-dark")
    }

    func testContactDraftAndTextEdit() {
        let app = launch()
        app.buttons["Запись"].tap()
        XCTAssertTrue(app.buttons["Добавить запись"].waitForExistence(timeout: 5))
        app.buttons["Добавить запись"].tap()
        let contact = app.buttons["Визитка"]
        XCTAssertTrue(contact.waitForExistence(timeout: 3))
        contact.tap()
        let name = input(app, "Имя")
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Анна")
        let phone = input(app, "Телефон")
        phone.tap()
        phone.typeText("79001112233")
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
        app.buttons["Добавить"].tap()
        XCTAssertTrue(app.staticTexts["Анна"].waitForExistence(timeout: 3))

        app.buttons["Убрать запись"].tap()
        XCTAssertTrue(app.buttons["Добавить запись"].waitForExistence(timeout: 3))
        app.buttons["Добавить запись"].tap()
        let text = input(app, "Текст")
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.tap()
        text.typeText("Старый текст")
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
        app.buttons["Добавить"].tap()
        let row = app.staticTexts["Старый текст"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()

        let editor = input(app, "Текст")
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let existing = (editor.value as? String) ?? ""
        if !existing.isEmpty {
            editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        editor.typeText("Новый текст")
        if app.buttons["Готово"].exists { app.buttons["Готово"].tap() }
        app.buttons["Сохранить"].tap()

        XCTAssertTrue(app.staticTexts["Новый текст"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Старый текст"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Убрать запись")).count, 1)
        attach(named: "edited-draft")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var lifts = 0
        while element.exists && (!element.isHittable || element.frame.midY > 680) && lifts < 6 {
            app.swipeUp()
            lifts += 1
        }
    }

    private func launch(seed: Bool = false, scan: Bool = false, language: String = "ru", locale: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-uiTesting", "-AppleLanguages", "(\(language))", "-AppleLocale", locale ?? (language == "ru" ? "ru_RU" : "en_US")]
        if seed { arguments.append("-seedLibrary") }
        if scan { arguments.append("-seedScan") }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func input(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let view = app.textViews[label]
        let field = app.textFields[label]
        if view.waitForExistence(timeout: 2) { return view }
        _ = field.waitForExistence(timeout: 2)
        return field
    }

    private func attach(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
