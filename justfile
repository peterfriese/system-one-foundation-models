# Task Runner for Jev Foundation Models & MailTriageApp

default:
    @just --list

# Swift Package tests (JevFoundationModels)
test:
    swift test

# Open MailTriageApp in Xcode
xcode-mail:
    open Examples/MailTriageApp/apps/apple/MailTriageApp.xcodeproj

# Apple Platform Builds & Tests (FlowDeck)
mail-build:
    flowdeck build -w Examples/MailTriageApp/apps/apple/MailTriageApp.xcodeproj -s MailTriageApp

mail-test:
    flowdeck test -w Examples/MailTriageApp/apps/apple/MailTriageApp.xcodeproj -s MailTriageApp

mail-test-core:
    flowdeck test --package-path Examples/MailTriageApp/apps/apple/Packages/AppCore

mail-test-ui:
    flowdeck test --package-path Examples/MailTriageApp/apps/apple/Packages/AppUI

# Simulator
sim-boot:
    flowdeck simulator boot "iPhone 16 Pro" || true
    open -a Simulator

