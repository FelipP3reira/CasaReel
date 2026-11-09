import Foundation

/// A string resource looked up in this package's String Catalog.
func dsString(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
}
