# Testes do app watchcollection

Guia rápido para LLMs e devs seguirem ao trabalhar na suíte de testes do app SwiftUI.

## Stack adotada
- **Swift Testing** (`import Testing`): novo framework da Apple para testes unitários e de integração leve, com `@Test` e `#expect`.
- **ViewInspector**: inspeção programática de SwiftUI para unit tests.
- **swift-snapshot-testing**: snapshots visuais para detectar regressões de UI.
- **XCUITest**: automação ponta a ponta em simulador/dispositivo.

## Layout dos alvos
- `swift-app/watchcollectionTests`: unit + snapshots (Swift Testing).
- `swift-app/watchcollectionUITests`: UI/integração (XCUITest).
- Pacotes SPM já configurados no `.xcodeproj`: ViewInspector `0.10.3` e SnapshotTesting `1.18.7`.

## Escrevendo testes com Swift Testing
```swift
import Testing
@testable import watchcollection

@Suite("MyFeature")
struct MyFeatureTests {
    @Test func doesSomething() async throws {
        let result = try await MyService().load()
        #expect(result.items.count > 0)
    }
}
```
- Use `#expect` para asserções; prefira múltiplas expectativas a um único assert.
- Agrupe por `@Suite` para clareza.
- Evite herança de `XCTestCase` nos novos testes unitários.

## Testando SwiftUI com ViewInspector
```swift
import ViewInspector
@testable import watchcollection

@Test func statCardShowsData() throws {
    let sut = StatCard(value: "25", label: "Watches", icon: "clock", color: .blue)
    let label = try sut.inspect().find(ViewType.Text.self) { try $0.string() == "Watches" }
    #expect(try label.string() == "Watches")
}

// Torne views inspecionáveis no alvo de teste
extension StatCard: Inspectable {}
```
- Sempre estenda as views personalizadas com `Inspectable` dentro do alvo de teste.
- Prefira buscar por texto/identificador em vez de posições específicas para reduzir fragilidade.

## Snapshots
- Arquivos de snapshot ficam em `swift-app/watchcollectionTests/__Snapshots__` por padrão.
- Exemplo (desabilitado por padrão até gravar baseline):
```swift
@Test(.disabled("Habilite ao gravar baseline"))
func statCardSnapshot() throws {
    let hosting = UIHostingController(rootView: StatCard(...))
    assertSnapshot(of: hosting, as: .image(on: .iPhone13Pro))
}
```
- Para gravar/atualizar baselines, habilite o teste e passe `record: true` ou defina `SnapshotTesting.isRecording = true` dentro do teste temporariamente.
- Rode apenas snapshots quando for registrar: `xcodebuild test -scheme watchcollection -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:watchcollectionTests/SnapshotTests`.

## UI / integração (XCUITest)
- Tests em `watchcollectionUITests`. Use identificadores de acessibilidade nas views (`.accessibilityIdentifier("addWatchButton")`) para seletores estáveis.
- Exemplo:
```swift
func testCanOpenSettingsTab() {
    let app = XCUIApplication()
    app.launch()
    app.tabBars.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
}
```
- Mantenha `continueAfterFailure = false` nos setups.

## Rodando testes
- Tudo: `xcodebuild test -scheme watchcollection -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`.
- Só unit (Swift Testing): `-only-testing:watchcollectionTests`.
- Só UI: `-only-testing:watchcollectionUITests`.
- Para execuções locais rápidas, selecione o esquema `watchcollection` no Xcode e marque/ desmarque os alvos em Test Navigator.

## Boas práticas
- Separe lógica de UI em view models ou serviços; facilita testar com `@Test` sem renderizar views.
- Injete dependências via protocolos (ou TCA `TestStore` se adotarmos TCA) para mocks previsíveis.
- Use `@MainActor` em testes que tocam UI/SwiftUI.
- Prefira dados determinísticos; evite relógio real e rede — crie fakes no alvo de teste.
- Documente novos helpers/utilities no próprio arquivo e reexporte em módulos de suporte se crescerem.

## Próximos passos sugeridos
1) Definir identificadores de acessibilidade para fluxos principais (add/edit watch, catálogo).
2) Adicionar um plano de teste no esquema para ativar cobertura e ordenar prioridades (unit antes de UI).
3) Gravar baselines iniciais de snapshot nos devices alvo do projeto.
