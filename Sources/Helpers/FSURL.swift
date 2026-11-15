import Foundation

enum FSURL {
    static var appContainers: URL {
        URL(fileURLWithPath: "/var/mobile/Containers/Data/Application")
    }
    
    static var appBundles: URL {
        URL(fileURLWithPath: "/var/containers/Bundle/Application")
    }
    
    static var sharedAppGroups: URL {
        URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup")
    }
    
    static var root: URL {
        URL(fileURLWithPath: "/")
    }
}