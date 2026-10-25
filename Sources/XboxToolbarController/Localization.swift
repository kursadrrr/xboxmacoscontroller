import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "en"
    case tr = "tr"
    case de = "de"
    case es = "es"
    case fr = "fr"
    case pt = "pt"
    case ru = "ru"
    case ja = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "🇬🇧 English"
        case .tr: return "🇹🇷 Türkçe"
        case .de: return "🇩🇪 Deutsch"
        case .es: return "🇪🇸 Español"
        case .fr: return "🇫🇷 Français"
        case .pt: return "🇵🇹 Português"
        case .ru: return "🇷🇺 Русский"
        case .ja: return "🇯🇵 日本語"
        }
    }

    var shortBadge: String {
        rawValue.uppercased()
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private let storageKey = "com.xboxiptv.language"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: saved) {
            self.language = lang
        } else {
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.hasPrefix("tr") {
                self.language = .tr
            } else if preferred.hasPrefix("de") {
                self.language = .de
            } else if preferred.hasPrefix("es") {
                self.language = .es
            } else if preferred.hasPrefix("fr") {
                self.language = .fr
            } else if preferred.hasPrefix("pt") {
                self.language = .pt
            } else if preferred.hasPrefix("ru") {
                self.language = .ru
            } else if preferred.hasPrefix("ja") {
                self.language = .ja
            } else {
                self.language = .en
            }
        }
    }

    // MARK: - Header & Status Strings

    func connectingTitle(_ ip: String) -> String {
        switch language {
        case .en: return "Connecting (\(ip))"
        case .tr: return "Bağlanıyor (\(ip))"
        case .de: return "Verbinde (\(ip))"
        case .es: return "Conectando (\(ip))"
        case .fr: return "Connexion (\(ip))"
        case .pt: return "Conectando (\(ip))"
        case .ru: return "Подключение (\(ip))"
        case .ja: return "接続中 (\(ip))"
        }
    }

    var scanningTitle: String {
        switch language {
        case .en: return "Scanning Xbox..."
        case .tr: return "Xbox Aranıyor..."
        case .de: return "Xbox wird gesucht..."
        case .es: return "Buscando Xbox..."
        case .fr: return "Recherche Xbox..."
        case .pt: return "Procurando Xbox..."
        case .ru: return "Поиск Xbox..."
        case .ja: return "Xboxを検索中..."
        }
    }

    var connectionErrorTitle: String {
        switch language {
        case .en: return "Connection Error"
        case .tr: return "Bağlantı Hatası"
        case .de: return "Verbindungsfehler"
        case .es: return "Error de conexión"
        case .fr: return "Erreur de connexion"
        case .pt: return "Erro de conexão"
        case .ru: return "Ошибка подключения"
        case .ja: return "接続エラー"
        }
    }

    var smartGlassActive: String {
        switch language {
        case .en: return "SmartGlass Active"
        case .tr: return "SmartGlass Aktif"
        case .de: return "SmartGlass Aktiv"
        case .es: return "SmartGlass Activo"
        case .fr: return "SmartGlass Actif"
        case .pt: return "SmartGlass Ativo"
        case .ru: return "SmartGlass активен"
        case .ja: return "SmartGlass 有効"
        }
    }

    var udpHandshakeSubtitle: String {
        switch language {
        case .en: return "UDP 5050 Handshake"
        case .tr: return "UDP 5050 El Sıkışması"
        case .de: return "UDP 5050 Handshake"
        case .es: return "Handshake UDP 5050"
        case .fr: return "Handshake UDP 5050"
        case .pt: return "Handshake UDP 5050"
        case .ru: return "Рукопожатие UDP 5050"
        case .ja: return "UDP 5050 ハンドシェイク"
        }
    }

    var scanningLanSubtitle: String {
        switch language {
        case .en: return "Scanning Local Network"
        case .tr: return "Yerel Ağ Taranıyor"
        case .de: return "Lokales Netzwerk scannen"
        case .es: return "Escaneando red local"
        case .fr: return "Scan du réseau local"
        case .pt: return "Verificando rede local"
        case .ru: return "Сканирование локальной сети"
        case .ja: return "ローカルネットワークをスキャン中"
        }
    }

    var clickToConnectSubtitle: String {
        switch language {
        case .en: return "Click to connect"
        case .tr: return "Bağlanmak için tıklayın"
        case .de: return "Klicken zum Verbinden"
        case .es: return "Clic para conectar"
        case .fr: return "Cliquer pour connecter"
        case .pt: return "Clique para conectar"
        case .ru: return "Нажмите для подключения"
        case .ja: return "クリックして接続"
        }
    }

    // MARK: - Header Menus & Tooltips

    var snapToToolbarHelp: String {
        switch language {
        case .en: return "Align Below Toolbar (Notch / Dynamic Island Safe Zone)"
        case .tr: return "Toolbar Altına Hizala (Notch / Dynamic Island Güvenli Bölge)"
        case .de: return "Unter Menüleiste ausrichten (Notch-sicherer Bereich)"
        case .es: return "Alinear bajo la barra (Zona segura del Notch)"
        case .fr: return "Aligner sous la barre (Zone sûre de l'encoche)"
        case .pt: return "Alinhar sob a barra (Zona segura do Notch)"
        case .ru: return "Выровнять под панелью (безопасная зона от выреза)"
        case .ja: return "メニューバーの下に揃える (ノッチ安全領域)"
        }
    }

    var snapToToolbarLabel: String {
        switch language {
        case .en: return "Align Below Toolbar"
        case .tr: return "Toolbar Altına Hizala"
        case .de: return "Unter Menüleiste ausrichten"
        case .es: return "Alinear bajo la barra"
        case .fr: return "Aligner sous la barre"
        case .pt: return "Alinhar sob a barra"
        case .ru: return "Выровнять под панелью"
        case .ja: return "メニューバー下に揃える"
        }
    }

    var wakeXboxLabel: String {
        switch language {
        case .en: return "Wake Xbox (Power On)"
        case .tr: return "Xbox'ı Uyandır (Power On)"
        case .de: return "Xbox aufwecken (Power On)"
        case .es: return "Encender Xbox (Power On)"
        case .fr: return "Allumer la Xbox (Power On)"
        case .pt: return "Ligar Xbox (Power On)"
        case .ru: return "Разбудить Xbox (Power On)"
        case .ja: return "Xboxを起動 (Power On)"
        }
    }

    var powerOffXboxLabel: String {
        switch language {
        case .en: return "Turn Off Xbox (Power Off)"
        case .tr: return "Xbox'ı Kapat (Power Off)"
        case .de: return "Xbox ausschalten (Power Off)"
        case .es: return "Apagar Xbox (Power Off)"
        case .fr: return "Éteindre la Xbox (Power Off)"
        case .pt: return "Desligar Xbox (Power Off)"
        case .ru: return "Выключить Xbox (Power Off)"
        case .ja: return "Xboxの電源を切る (Power Off)"
        }
    }

    var scanConsolesLabel: String {
        switch language {
        case .en: return "Scan Xbox on Network (UDP 5050)"
        case .tr: return "Ağda Xbox Tara (UDP 5050)"
        case .de: return "Xbox im Netzwerk suchen (UDP 5050)"
        case .es: return "Buscar Xbox en la red (UDP 5050)"
        case .fr: return "Scanner Xbox sur le réseau (UDP 5050)"
        case .pt: return "Procurar Xbox na rede (UDP 5050)"
        case .ru: return "Найти Xbox в сети (UDP 5050)"
        case .ja: return "ネットワーク上のXboxをスキャン (UDP 5050)"
        }
    }

    var disconnectLabel: String {
        switch language {
        case .en: return "Disconnect"
        case .tr: return "Bağlantıyı Kes"
        case .de: return "Trennen"
        case .es: return "Desconectar"
        case .fr: return "Déconnecter"
        case .pt: return "Desconectar"
        case .ru: return "Отключиться"
        case .ja: return "切断する"
        }
    }

    var powerMenuHelp: String {
        switch language {
        case .en: return "Power & Connection Options"
        case .tr: return "Güç ve Bağlantı Seçenekleri"
        case .de: return "Energie- & Verbindungsoptionen"
        case .es: return "Opciones de energía y conexión"
        case .fr: return "Options d'alimentation et de connexion"
        case .pt: return "Opções de energia e conexão"
        case .ru: return "Питание и подключение"
        case .ja: return "電源と接続のオプション"
        }
    }

    var languageMenuHelp: String {
        switch language {
        case .en: return "Change Language / Dil Seçimi"
        case .tr: return "Dil Seçimi / Change Language"
        case .de: return "Sprache ändern / Change Language"
        case .es: return "Cambiar idioma / Change Language"
        case .fr: return "Changer de langue / Change Language"
        case .pt: return "Mudar idioma / Change Language"
        case .ru: return "Изменить язык / Change Language"
        case .ja: return "言語を変更 / Change Language"
        }
    }

    func pinHelp(isPinned: Bool) -> String {
        switch language {
        case .en: return isPinned ? "Pinned on Screen (Click to unpin)" : "Pin Controller on Screen (Always on Top)"
        case .tr: return isPinned ? "Ekrana Sabitlendi (Kaldırmak için tıklayın)" : "Kumandayı Ekrana Sabitle (Her zaman üstte)"
        case .de: return isPinned ? "Angeheftet (Klicken zum Lösen)" : "Controller anheften (Immer im Vordergrund)"
        case .es: return isPinned ? "Fijado en pantalla (Clic para soltar)" : "Fijar mando en pantalla (Siempre visible)"
        case .fr: return isPinned ? "Épinglé à l'écran (Cliquer pour détacher)" : "Épingler la manette (Toujours au premier plan)"
        case .pt: return isPinned ? "Fixado na tela (Clique para soltar)" : "Fixar controle na tela (Sempre no topo)"
        case .ru: return isPinned ? "Закреплено (нажмите, чтобы открепить)" : "Закрепить пульт поверх всех окон"
        case .ja: return isPinned ? "画面に固定中 (クリックで解除)" : "コントローラーを最前面に固定"
        }
    }

    // MARK: - Connection Drawer

    var ipPlaceholder: String {
        switch language {
        case .en: return "Xbox IP Address (e.g. 192.168.1.45)"
        case .tr: return "Xbox IP Adresi (örn: 192.168.1.45)"
        case .de: return "Xbox IP-Adresse (z.B. 192.168.1.45)"
        case .es: return "Dirección IP de Xbox (ej: 192.168.1.45)"
        case .fr: return "Adresse IP Xbox (ex: 192.168.1.45)"
        case .pt: return "Endereço IP do Xbox (ex: 192.168.1.45)"
        case .ru: return "IP-адрес Xbox (напр., 192.168.1.45)"
        case .ja: return "Xbox IPアドレス (例: 192.168.1.45)"
        }
    }

    var connectButton: String {
        switch language {
        case .en: return "Connect"
        case .tr: return "Bağlan"
        case .de: return "Verbinden"
        case .es: return "Conectar"
        case .fr: return "Connecter"
        case .pt: return "Conectar"
        case .ru: return "Подключить"
        case .ja: return "接続"
        }
    }

    var scanLanHelp: String {
        switch language {
        case .en: return "Scan for Xbox consoles on local network"
        case .tr: return "Yerel ağdaki Xbox'ları tara"
        case .de: return "Xbox-Konsolen im lokalen Netzwerk suchen"
        case .es: return "Buscar consolas Xbox en la red local"
        case .fr: return "Rechercher des consoles Xbox sur le réseau local"
        case .pt: return "Procurar consoles Xbox na rede local"
        case .ru: return "Сканировать консоли Xbox в локальной сети"
        case .ja: return "ローカルネットワーク内のXboxをスキャン"
        }
    }

    // MARK: - Gamepad Buttons & D-Pad

    var backSubtitle: String {
        switch language {
        case .en: return "Back"
        case .tr: return "Geri"
        case .de: return "Zurück"
        case .es: return "Atrás"
        case .fr: return "Retour"
        case .pt: return "Voltar"
        case .ru: return "Назад"
        case .ja: return "戻る"
        }
    }

    var searchSubtitle: String {
        switch language {
        case .en: return "Search"
        case .tr: return "Ara"
        case .de: return "Suche"
        case .es: return "Buscar"
        case .fr: return "Rechercher"
        case .pt: return "Buscar"
        case .ru: return "Поиск"
        case .ja: return "検索"
        }
    }

    var xButtonSuffix: String {
        switch language {
        case .en: return "Button"
        case .tr: return "Tuşu"
        case .de: return "Taste"
        case .es: return "Botón"
        case .fr: return "Bouton"
        case .pt: return "Botão"
        case .ru: return "Кнопка"
        case .ja: return "ボタン"
        }
    }

    var selectCenterLabel: String {
        switch language {
        case .en: return "SELECT"
        case .tr: return "SEÇ"
        case .de: return "OK"
        case .es: return "OK"
        case .fr: return "OK"
        case .pt: return "OK"
        case .ru: return "ВЫБОР"
        case .ja: return "決定"
        }
    }

    var directionModeLabel: String {
        switch language {
        case .en: return "Nav Mode:"
        case .tr: return "Yön Modu:"
        case .de: return "Modus:"
        case .es: return "Modo:"
        case .fr: return "Mode :"
        case .pt: return "Modo:"
        case .ru: return "Режим:"
        case .ja: return "方向モード:"
        }
    }

    var modeAllLabel: String {
        switch language {
        case .en: return "Both"
        case .tr: return "Tümü"
        case .de: return "Beide"
        case .es: return "Ambos"
        case .fr: return "Tous"
        case .pt: return "Ambos"
        case .ru: return "Все"
        case .ja: return "すべて"
        }
    }

    // MARK: - IPTV & Media Section

    var reviveIptvButton: String {
        switch language {
        case .en: return "Unfreeze IPTV Stream"
        case .tr: return "Donan IPTV'yi Canlandır"
        case .de: return "IPTV-Stream neu laden"
        case .es: return "Reanimar IPTV congelado"
        case .fr: return "Relancer le flux IPTV"
        case .pt: return "Destravar stream IPTV"
        case .ru: return "Оживить зависший IPTV"
        case .ja: return "フリーズしたIPTVを再読込"
        }
    }

    var reviveModeTitle: String {
        switch language {
        case .en: return "Stream Recovery Mode"
        case .tr: return "Canlandırma Modu"
        case .de: return "Wiederherstellungsmodus"
        case .es: return "Modo de recuperación"
        case .fr: return "Mode de relance"
        case .pt: return "Modo de recuperação"
        case .ru: return "Режим перезапуска"
        case .ja: return "ストリーム復帰モード"
        }
    }

    var reviveMode1: String {
        switch language {
        case .en: return "Mode 1: Channel Down -> Up (CH- / CH+)"
        case .tr: return "Mod 1: Kanal Aşağı -> Yukarı (CH- / CH+)"
        case .de: return "Modus 1: Kanal runter -> hoch (CH- / CH+)"
        case .es: return "Modo 1: Canal abajo -> arriba (CH- / CH+)"
        case .fr: return "Mode 1 : Chaîne - -> Chaîne + (CH- / CH+)"
        case .pt: return "Modo 1: Canal baixo -> cima (CH- / CH+)"
        case .ru: return "Режим 1: Канал вниз -> вверх (CH- / CH+)"
        case .ja: return "モード1: チャンネル下 -> 上 (CH- / CH+)"
        }
    }

    var reviveMode2: String {
        switch language {
        case .en: return "Mode 2: Exit -> Re-enter (B -> A)"
        case .tr: return "Mod 2: Geri Çık -> Tekrar Gir (B -> A)"
        case .de: return "Modus 2: Zurück -> Auswahl (B -> A)"
        case .es: return "Modo 2: Salir -> Volver a entrar (B -> A)"
        case .fr: return "Mode 2 : Retour -> Sélectionner (B -> A)"
        case .pt: return "Modo 2: Voltar -> Entrar novamente (B -> A)"
        case .ru: return "Режим 2: Выход -> Повторный вход (B -> A)"
        case .ja: return "モード2: 戻る -> 再選択 (B -> A)"
        }
    }

    var reviveMode3: String {
        switch language {
        case .en: return "Mode 3: Stop -> Play"
        case .tr: return "Mod 3: Durdur -> Oynat (Stop -> Play)"
        case .de: return "Modus 3: Stopp -> Wiedergabe (Stop -> Play)"
        case .es: return "Modo 3: Detener -> Reproducir (Stop -> Play)"
        case .fr: return "Mode 3 : Arrêter -> Lecture (Stop -> Play)"
        case .pt: return "Modo 3: Parar -> Reproduzir (Stop -> Play)"
        case .ru: return "Режим 3: Стоп -> Воспроизведение (Stop -> Play)"
        case .ja: return "モード3: 停止 -> 再生 (Stop -> Play)"
        }
    }

    var reviveIptvHelp: String {
        switch language {
        case .en: return "Reloads a frozen IPTV stream with 1 click (Right-click to choose mode)"
        case .tr: return "Donan IPTV yayınını tek tıkla yeniler (Sağ tık ile mod seçin)"
        case .de: return "Lädt eingefrorene IPTV-Streams neu (Rechtsklick für Modus)"
        case .es: return "Recarga un stream IPTV congelado con 1 clic (Clic derecho para modo)"
        case .fr: return "Relance un flux IPTV figé en 1 clic (Clic droit pour le mode)"
        case .pt: return "Recarrega um stream IPTV travado com 1 clique (Clique direito para modo)"
        case .ru: return "Перезапускает зависший поток IPTV в 1 клик (ПКМ для выбора режима)"
        case .ja: return "1クリックでIPTVストリームを再読込 (右クリックでモード変更)"
        }
    }

    // MARK: - Keyboard & Text Input Section

    func keyboardTitle(active: Bool) -> String {
        switch language {
        case .en: return active ? "Xbox On-Screen Keyboard Active" : "Xbox / Kodi Keyboard"
        case .tr: return active ? "Xbox Ekran Klavyesi Açık (Hazır)" : "Xbox / Kodi Klavye"
        case .de: return active ? "Xbox-Bildschirmtastatur aktiv" : "Xbox / Kodi Tastatur"
        case .es: return active ? "Teclado en pantalla Xbox activo" : "Teclado Xbox / Kodi"
        case .fr: return active ? "Clavier visuel Xbox actif" : "Clavier Xbox / Kodi"
        case .pt: return active ? "Teclado na tela do Xbox ativo" : "Teclado Xbox / Kodi"
        case .ru: return active ? "Экранная клавиатура Xbox активна" : "Клавиатура Xbox / Kodi"
        case .ja: return active ? "Xbox 画面キーボード有効" : "Xbox / Kodi キーボード"
        }
    }

    var pasteAndSendButton: String {
        switch language {
        case .en: return "Paste & Send"
        case .tr: return "Yapıştır & Gönder"
        case .de: return "Einfügen & Senden"
        case .es: return "Pegar y Enviar"
        case .fr: return "Coller & Envoyer"
        case .pt: return "Colar e Enviar"
        case .ru: return "Вставить"
        case .ja: return "貼付して送信"
        }
    }

    var pasteAndSendHelp: String {
        switch language {
        case .en: return "Pastes text from macOS clipboard (Cmd+C) and sends it to Xbox/Kodi"
        case .tr: return "Mac panosundaki (Cmd+C) metni tek tıkla Xbox/Kodi'ye yapıştırır ve gönderir"
        case .de: return "Fügt Text aus der Zwischenablage ein und sendet ihn an Xbox/Kodi"
        case .es: return "Pega el texto del portapapeles de Mac y lo envía a Xbox/Kodi"
        case .fr: return "Colle le texte du presse-papiers Mac et l'envoie à Xbox/Kodi"
        case .pt: return "Cola o texto da área de transferência do Mac e envia ao Xbox/Kodi"
        case .ru: return "Вставляет текст из буфера обмена Mac и отправляет на Xbox/Kodi"
        case .ja: return "Macのクリップボードからテキストを貼り付けてXbox/Kodiに送信"
        }
    }

    var shortcutsToggle: String {
        switch language {
        case .en: return "Keys"
        case .tr: return "Kısayollar"
        case .de: return "Tasten"
        case .es: return "Atajos"
        case .fr: return "Raccourcis"
        case .pt: return "Atalhos"
        case .ru: return "Хоткеи"
        case .ja: return "キー操作"
        }
    }

    var textFieldPlaceholder: String {
        switch language {
        case .en: return "Paste text or M3U URL (Cmd+V)..."
        case .tr: return "Metin veya M3U URL yapıştırın (Cmd+V)..."
        case .de: return "Text oder M3U-URL einfügen (Cmd+V)..."
        case .es: return "Pegar texto o URL M3U (Cmd+V)..."
        case .fr: return "Coller du texte ou une URL M3U (Cmd+V)..."
        case .pt: return "Cole texto ou URL M3U (Cmd+V)..."
        case .ru: return "Вставьте текст или M3U URL (Cmd+V)..."
        case .ja: return "テキストまたはM3U URLを貼り付け (Cmd+V)..."
        }
    }

    var sendButton: String {
        switch language {
        case .en: return "Send"
        case .tr: return "Gönder"
        case .de: return "Senden"
        case .es: return "Enviar"
        case .fr: return "Envoyer"
        case .pt: return "Enviar"
        case .ru: return "Отпр."
        case .ja: return "送信"
        }
    }

    var clipboardEmptyStatus: String {
        switch language {
        case .en: return "Clipboard is empty."
        case .tr: return "Panoda metin bulunamadı."
        case .de: return "Zwischenablage ist leer."
        case .es: return "El portapapeles está vacío."
        case .fr: return "Le presse-papiers est vide."
        case .pt: return "A área de transferência está vazia."
        case .ru: return "Буфер обмена пуст."
        case .ja: return "クリップボードが空です。"
        }
    }

    var quitButton: String {
        switch language {
        case .en: return "Quit"
        case .tr: return "Çıkış"
        case .de: return "Beenden"
        case .es: return "Salir"
        case .fr: return "Quitter"
        case .pt: return "Sair"
        case .ru: return "Выход"
        case .ja: return "終了"
        }
    }

    // MARK: - SmartGlass Status Messages

    var readyStatus: String {
        switch language {
        case .en: return "Controller ready (Gamepad + Media + Keyboard active)"
        case .tr: return "Kumanda hazır (Gamepad + Medya + Klavye aktif)"
        case .de: return "Controller bereit (Gamepad + Medien + Tastatur aktiv)"
        case .es: return "Mando listo (Gamepad + Multimedia + Teclado activo)"
        case .fr: return "Manette prête (Gamepad + Média + Clavier actif)"
        case .pt: return "Controle pronto (Gamepad + Mídia + Teclado ativo)"
        case .ru: return "Пульт готов (Геймпад + Медиа + Клавиатура активны)"
        case .ja: return "コントローラー準備完了 (ゲームパッド + メディア + キーボード)"
        }
    }

    func buttonLabel(_ button: GamepadButton) -> String {
        switch button {
        case .nexus: return "Xbox Home"
        case .view: return "View"
        case .menu: return "Menu"
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .leftShoulder: return "LB"
        case .rightShoulder: return "RB"
        case .up:
            switch language {
            case .en: return "Up"
            case .tr: return "Yukarı"
            case .de: return "Oben"
            case .es: return "Arriba"
            case .fr: return "Haut"
            case .pt: return "Cima"
            case .ru: return "Вверх"
            case .ja: return "上"
            }
        case .down:
            switch language {
            case .en: return "Down"
            case .tr: return "Aşağı"
            case .de: return "Unten"
            case .es: return "Abajo"
            case .fr: return "Bas"
            case .pt: return "Baixo"
            case .ru: return "Вниз"
            case .ja: return "下"
            }
        case .left:
            switch language {
            case .en: return "Left"
            case .tr: return "Sol"
            case .de: return "Links"
            case .es: return "Izquierda"
            case .fr: return "Gauche"
            case .pt: return "Esquerda"
            case .ru: return "Влево"
            case .ja: return "左"
            }
        case .right:
            switch language {
            case .en: return "Right"
            case .tr: return "Sağ"
            case .de: return "Rechts"
            case .es: return "Derecha"
            case .fr: return "Droite"
            case .pt: return "Direita"
            case .ru: return "Вправо"
            case .ja: return "右"
            }
        }
    }
}
