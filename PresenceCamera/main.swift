import CoreMediaIO
import Foundation

let providerSource = PresenceProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
