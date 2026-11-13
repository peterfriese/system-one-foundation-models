# Task Runner for Jev Foundation Models & MailTriageApp

default:
    @just --list

# Swift Package tests (JevFoundationModels)
test:
    swift test

# Open MailTriageApp in Xcode
xcode-mail:
    open Examples/Apps/MailTriageApp/apps/apple/MailTriageApp.xcodeproj

# Apple Platform Builds & Tests (FlowDeck 1.26.5+)
mail-build:
    flowdeck build -w Examples/Apps/MailTriageApp/apps/apple/MailTriageApp.xcodeproj -s MailTriageApp -S "iPhone 18 Pro"

mail-test: mail-test-core mail-test-ui

mail-test-core:
    flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppCore -s AppCore-Package -S "iPhone 18 Pro"

mail-test-ui:
    flowdeck test -p Examples/Apps/MailTriageApp/apps/apple/Packages/AppUI -s AppUI -S "iPhone 18 Pro"

# Simulator
sim-boot:
    flowdeck simulator boot "iPhone 18 Pro" || true
    open -a Simulator

