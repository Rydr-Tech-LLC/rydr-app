import Foundation

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

enum RydrCrashReporter {
    static func record(_ error: Error, context: String) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCustomValue(context, forKey: "rydr_context")
        Crashlytics.crashlytics().record(error: error)
        #else
        print("RydrCrashReporter[\(context)]: \(error.localizedDescription)")
        #endif
    }

    static func log(_ message: String) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log(message)
        #else
        print("RydrCrashReporter: \(message)")
        #endif
    }
}
