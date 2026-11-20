// EH3D-IOS-CONTROL - looks for EH3D-SERVER on the local network (Bonjour / mDNS, the service `_eh3d._tcp`) with Network.framework.
// It is used only when the person turned the search on (it is off by default) and it only reports what the network answered: a name that answered proves nothing, so the person chooses and the sign-in still
// asks for the password. Only IPv4 addresses are reported (an address with a scope cannot be written as host:port). The first search asks the person for the permission of the local network
// (`NSLocalNetworkUsageDescription`, with `_eh3d._tcp` in `NSBonjourServices`). Nothing here has run on an iPhone.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation
import Network
import Eh3dCore

final class ServerDiscovery {
    private let queue = DispatchQueue(label: "es.electrohobby3d.eh3d.discovery")
    private let onFound: @Sendable (String, Int) -> Void
    private var browser: NWBrowser?
    private var probes: [NWConnection] = []
    private var seen = Set<String>()
    private var stopped = false

    init(onFound: @escaping @Sendable (String, Int) -> Void) { self.onFound = onFound }

    func start() {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results { self.resolve(result.endpoint) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.stop() }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.browser?.cancel()
            self.browser = nil
            self.probes.forEach { $0.cancel() }
            self.probes.removeAll()
        }
    }

    /// A service is resolved by opening the connection to it and reading where it went (only IPv4); the connection carries nothing and is closed at once.
    /// At most `maxCandidates` services are looked at, so a network full of answers costs nothing.
    private func resolve(_ endpoint: NWEndpoint) {
        let key = "\(endpoint)"
        if stopped || seen.contains(key) || seen.count >= maxCandidates { return }
        seen.insert(key)
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let probe = NWConnection(to: endpoint, using: parameters)
        probe.stateUpdateHandler = { [weak self, weak probe] state in
            guard let self, let probe else { return }
            switch state {
            case .ready:
                if case let .hostPort(host, port)? = probe.currentPath?.remoteEndpoint, case let .ipv4(address) = host, !self.stopped {
                    // the text of an address can carry the interface (`192.168.0.5%en0`): only the address is kept
                    let text = "\(address)".split(separator: "%").first.map(String.init) ?? ""
                    self.onFound(text, Int(port.rawValue))
                }
                probe.cancel()
            case .failed:
                probe.cancel()
            default:
                break
            }
        }
        probes.append(probe)
        probe.start(queue: queue)
    }
}
