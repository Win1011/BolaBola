//
//  IOSOnboardingView.swift
//

import AuthenticationServices
import HealthKit
import SwiftUI
import UIKit
import UserNotifications

struct IOSOnboardingView: View {
    var onDone: () -> Void

    @State private var stepIndex = 0
    @State private var visibleStepID: Int? = 0
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var healthRequested = false
    @State private var userNickname = ""
    @State private var birthDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .now
    @State private var selectedGender: OnboardingGender?
    @State private var bolaNickname = ""

    private let healthStore = HKHealthStore()
    private let stepCount = 11

    var body: some View {
        ZStack(alignment: .top) {
            BolaOnboardingAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topChrome

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        WelcomeLoginPage(isActive: stepIndex == 0, onContinue: { goToStep(1) })
                            .onboardingPage(id: 0)
                        IntroCompanionPage(
                            isActive: stepIndex == 1,
                            onContinue: { goToStep(2) }
                        )
                            .onboardingPage(id: 1)
                        LevelUpPage(isActive: stepIndex == 2, onContinue: { goToStep(3) })
                            .onboardingPage(id: 2)
                        NotificationPermissionPage(
                            isActive: stepIndex == 3,
                            status: notificationStatus,
                            onAllow: requestNotifications,
                            onSkip: { goToStep(4) }
                        )
                        .onboardingPage(id: 3)
                        HealthRhythmPage(
                            isActive: stepIndex == 4,
                            requested: healthRequested,
                            onContinue: requestHealthAccess
                        )
                        .onboardingPage(id: 4)
                        QuestionIntroPage(isActive: stepIndex == 5, onContinue: { goToStep(6) })
                            .onboardingPage(id: 5)
                        UserNicknamePage(
                            isActive: stepIndex == 6,
                            nickname: $userNickname,
                            onContinue: { goToStep(7) }
                        )
                        .onboardingPage(id: 6)
                        BirthdayPage(
                            isActive: stepIndex == 7,
                            birthDate: $birthDate,
                            onContinue: { goToStep(8) }
                        )
                        .onboardingPage(id: 7)
                        GenderPage(
                            isActive: stepIndex == 8,
                            selectedGender: $selectedGender,
                            onContinue: { goToStep(9) }
                        )
                        .onboardingPage(id: 8)
                        BolaNicknamePage(
                            isActive: stepIndex == 9,
                            nickname: $bolaNickname,
                            onContinue: { goToStep(10) }
                        )
                        .onboardingPage(id: 9)
                        ReadyPage(isActive: stepIndex == 10, onEnter: finishOnboarding)
                            .onboardingPage(id: 10)
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleStepID)
                .scrollDisabled(!(5...9).contains(stepIndex))
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: stepIndex)
                .onChange(of: visibleStepID) { _, newID in
                    guard let newID, (5...9).contains(newID), newID != stepIndex else { return }
                    stepIndex = newID
                }
            }

            #if DEBUG
            VStack(spacing: 8) {
                Button {
                    goToStep(stepIndex - 1)
                } label: {
                    Text("上一页")
                        .onboardingDebugButtonLabel()
                }
                .opacity(stepIndex > 0 ? 1 : 0)
                .disabled(stepIndex <= 0)

                Button {
                    goToStep(stepIndex + 1)
                } label: {
                    Text("下一页")
                        .onboardingDebugButtonLabel()
                }
                .opacity(stepIndex < stepCount - 1 ? 1 : 0)
                .disabled(stepIndex >= stepCount - 1)
            }
            .buttonStyle(.plain)
            .padding(.top, 54)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .trailing)
            #endif
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
            let draft = OnboardingDraft.load()
            userNickname = draft.userNickname
            birthDate = draft.birthDate
            selectedGender = draft.gender
            bolaNickname = draft.bolaNickname
        }
        .onChange(of: userNickname) { _, _ in persistDraft() }
        .onChange(of: birthDate) { _, _ in persistDraft() }
        .onChange(of: selectedGender) { _, _ in persistDraft() }
        .onChange(of: bolaNickname) { _, _ in persistDraft() }
        .onChange(of: visibleStepID) { _, newValue in
            guard let newValue, (0 ..< stepCount).contains(newValue) else { return }
            stepIndex = newValue
        }
    }

    @ViewBuilder
    private var topChrome: some View {
        if (5 ... 9).contains(stepIndex) {
            VStack {
                Spacer()
                ProgressPills(currentIndex: min(max(stepIndex - 5, 0), 3), total: 4)
                    .padding(.horizontal, 58)
                Spacer()
            }
            .frame(height: 56)
        } else {
            Color.clear
                .frame(height: 28)
        }
    }

    private func requestNotifications() {
        guard notificationStatus != .authorized && notificationStatus != .provisional else {
            goToStep(4)
            return
        }

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationStatus = settings.authorizationStatus
                goToStep(4)
            }
        }
    }

    private func requestHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else {
            goToStep(5)
            return
        }

        var types = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleStandTime) { types.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(t) }

        healthStore.requestAuthorization(toShare: [], read: types) { _, _ in
            DispatchQueue.main.async {
                healthRequested = true
                UserDefaults.standard.set(true, forKey: IOSHealthHabitAnalysisModel.healthReadPromptCompletedKey)
                goToStep(5)
            }
        }
    }

    private func persistDraft() {
        let draft = OnboardingDraft(
            userNickname: userNickname,
            birthDate: birthDate,
            gender: selectedGender,
            bolaNickname: bolaNickname
        )
        draft.save()
    }

    private func finishOnboarding() {
        persistDraft()
        BolaOnboardingState.markCompleted()
        onDone()
    }

    private func goToStep(_ index: Int) {
        let clampedIndex = min(max(index, 0), stepCount - 1)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            stepIndex = clampedIndex
            visibleStepID = clampedIndex
        }
    }
}

private struct BolaOnboardingAmbientBackground: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let topDiameter = min(max(width * 1.9, 700), 820)
            let bottomDiameter = max(width * 2.35, 880)

            Color.white
                .overlay(alignment: .top) {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    BolaTheme.accent.opacity(0.98),
                                    BolaTheme.accent.opacity(0.6),
                                    BolaTheme.accent.opacity(0.16),
                                    Color.white.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: topDiameter * 0.5
                            )
                        )
                        .frame(width: topDiameter, height: topDiameter * 0.62)
                        .blur(radius: 34)
                        .offset(y: -topDiameter * 0.35)
                }
                .overlay(alignment: .bottom) {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    BolaTheme.accent.opacity(0.98),
                                    BolaTheme.accent.opacity(0.6),
                                    Color.white.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: bottomDiameter * 0.5
                            )
                        )
                        .frame(width: bottomDiameter, height: bottomDiameter * 0.62)
                        .blur(radius: 34)
                        .offset(y: bottomDiameter * 0.43 + 60)
                }
        }
        .background(Color.white)
        .allowsHitTesting(false)
    }
}

private struct OnboardingDraft {
    var userNickname: String
    var birthDate: Date
    var gender: OnboardingGender?
    var bolaNickname: String

    private static let userNicknameKey = "bola_onboarding_user_nickname_v1"
    private static let birthDateKey = "bola_onboarding_birth_date_v1"
    private static let genderKey = "bola_onboarding_gender_v1"
    private static let bolaNicknameKey = "bola_onboarding_bola_nickname_v1"

    static func load() -> OnboardingDraft {
        let defaults = UserDefaults.standard
        let ts = defaults.object(forKey: birthDateKey) as? TimeInterval
        return OnboardingDraft(
            userNickname: defaults.string(forKey: userNicknameKey) ?? "",
            birthDate: ts.map(Date.init(timeIntervalSinceReferenceDate:)) ?? Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .now,
            gender: OnboardingGender(rawValue: defaults.string(forKey: genderKey) ?? ""),
            bolaNickname: defaults.string(forKey: bolaNicknameKey) ?? ""
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(userNickname.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.userNicknameKey)
        defaults.set(birthDate.timeIntervalSinceReferenceDate, forKey: Self.birthDateKey)
        defaults.set(gender?.rawValue, forKey: Self.genderKey)
        defaults.set(bolaNickname.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.bolaNicknameKey)
    }
}

private enum OnboardingGender: String, CaseIterable, Identifiable {
    case female
    case male
    case nonBinary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return "女生"
        case .male: return "男生"
        case .nonBinary: return "其他"
        }
    }
}

private struct ProgressPills: View {
    let currentIndex: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< total, id: \.self) { index in
                Capsule()
                    .fill(index <= currentIndex ? BolaTheme.accent : Color.white.opacity(0.92))
                    .frame(height: 5)
                    .shadow(color: BolaTheme.accent.opacity(index <= currentIndex ? 0.28 : 0), radius: 8, x: 0, y: 2)
            }
        }
    }
}

private struct OnboardingScreen<Content: View>: View {
    @ViewBuilder let content: Content
    let isActive: Bool
    var animateEntrance: Bool = true
    var scrollsWithKeyboard: Bool = false
    let primaryTitle: String
    let primaryAction: () -> Void
    var isPrimaryDisabled = false
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    init(
        isActive: Bool = true,
        animateEntrance: Bool = true,
        scrollsWithKeyboard: Bool = false,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        isPrimaryDisabled: Bool = false,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.isActive = isActive
        self.animateEntrance = animateEntrance
        self.scrollsWithKeyboard = scrollsWithKeyboard
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.isPrimaryDisabled = isPrimaryDisabled
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
            }
            .scrollDisabled(!scrollsWithKeyboard)

            VStack(spacing: 10) {
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.35))
                }

                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BolaTheme.onAccentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(isPrimaryDisabled ? Color.black.opacity(0.08) : BolaTheme.accent)
                        .clipShape(Capsule())
                }
                .disabled(isPrimaryDisabled)
                .opacity(isPrimaryDisabled ? 0.72 : 1)
            }
            .modifier(ConditionalEntranceModifier(isActive: isActive, index: 4, animate: animateEntrance))
            .padding(.horizontal, 36)
            .padding(.bottom, 18)
        }
    }
}

private extension View {
    func onboardingBlockEntrance(
        isActive: Bool,
        index: Int,
        baseDelay: TimeInterval = 0.16,
        stepDelay: TimeInterval = 0.18
    ) -> some View {
        modifier(
            OnboardingBlockEntranceModifier(
                isActive: isActive,
                delay: baseDelay + Double(index) * stepDelay
            )
        )
    }

    func onboardingDebugButtonLabel() -> some View {
        font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black.opacity(0.78))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.white.opacity(0.86))
            .clipShape(Capsule())
    }

    func onboardingPage(id: Int) -> some View {
        self
            .containerRelativeFrame(.horizontal)
            .id(id)
    }
}

private struct ConditionalEntranceModifier: ViewModifier {
    let isActive: Bool
    let index: Int
    let animate: Bool

    func body(content: Content) -> some View {
        if animate {
            content.onboardingBlockEntrance(isActive: isActive, index: index)
        } else {
            content
        }
    }
}

private struct OnboardingBlockEntranceModifier: ViewModifier {
    let isActive: Bool
    let delay: TimeInterval

    @State private var isVisible = false
    @State private var runID = 0

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .animation(.spring(response: 0.82, dampingFraction: 0.93), value: isVisible)
            .onAppear {
                if isActive {
                    replay(after: delay)
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    replay(after: delay)
                } else {
                    reset()
                }
            }
    }

    private func replay(after delay: TimeInterval) {
        reset()
        let currentRunID = runID
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard currentRunID == runID, isActive else { return }
            isVisible = true
        }
    }

    private func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            runID += 1
            isVisible = false
        }
    }
}

private struct WelcomeLoginPage: View {
    let isActive: Bool
    let onContinue: () -> Void
    @State private var signInErrorMessage: String?
    @State private var hasSignedInWithApple = BolaAppleSignInState.isSignedIn
    @State private var hasAcceptedLegal = true

    private let termsURL = URL(string: "https://bolabola.app/terms")!
    private let privacyURL = URL(string: "https://bolabola.app/privacy")!
    private let legalLinkColor = Color(red: 0x5D / 255, green: 0x6A / 255, blue: 0x07 / 255)

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            VStack(spacing: 10) {
                Text("欢迎来到")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("BolaBola")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, -15)

                Image("OnboardingWelcomeTagline")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 279, height: 101)
                    .padding(.top, 5)
            }
            .onboardingBlockEntrance(isActive: isActive, index: 0)

            Spacer(minLength: 12)

            GeometryReader { proxy in
                Image("OnboardingWelcomeHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(402, proxy.size.width))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: min(290, UIScreen.main.bounds.width * 290 / 402))
            .onboardingBlockEntrance(isActive: isActive, index: 1)

            Spacer(minLength: 30)

            VStack(spacing: 0) {
                OnboardingBundleImage(
                    filename: "OnboardingBolaMark",
                    size: CGSize(width: 40, height: 28)
                )
                .offset(y: -6)

                Text("欢迎来到BolaBola")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.top, 10)

                Text("和 Bola 一起让每一天变得更好吧！")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0xA5 / 255, green: 0xAE / 255, blue: 0x66 / 255))
                    .padding(.top, 4)
            }
            .onboardingBlockEntrance(isActive: isActive, index: 2)

            SignInWithAppleButton(hasSignedInWithApple ? .continue : .signIn) { request in
                signInErrorMessage = nil
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignInCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .clipShape(Capsule())
            .disabled(!hasAcceptedLegal)
            .opacity(hasAcceptedLegal ? 1 : 0.42)
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .onboardingBlockEntrance(isActive: isActive, index: 3)
            .onAppear {
                hasSignedInWithApple = BolaAppleSignInState.isSignedIn
            }

            if let signInErrorMessage {
                Text(signInErrorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 10)
            }

            HStack(spacing: 8) {
                Button {
                    hasAcceptedLegal.toggle()
                } label: {
                    Image(systemName: hasAcceptedLegal ? "checkmark.square.fill" : "square")
                        .font(.system(size: 10))
                        .foregroundStyle(hasAcceptedLegal ? legalLinkColor : Color.black.opacity(0.28))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasAcceptedLegal ? "取消同意用户协议和隐私政策" : "同意用户协议和隐私政策")

                HStack(spacing: 0) {
                    Text("点击登录即表示你同意《")
                    Link("用户协议", destination: termsURL)
                        .foregroundStyle(legalLinkColor)
                    Text("》和《")
                    Link("隐私政策", destination: privacyURL)
                        .foregroundStyle(legalLinkColor)
                    Text("》。")
                }
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.35))
            .padding(.top, 14)
            .padding(.bottom, 10)
            .onboardingBlockEntrance(isActive: isActive, index: 4)
        }
    }

    private func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInErrorMessage = "Apple 登录没有返回有效凭证，请再试一次。"
                return
            }
            BolaAppleSignInState.markSignedIn(
                userIdentifier: credential.user,
                fullName: credential.fullName,
                email: credential.email
            )
            hasSignedInWithApple = true
            onContinue()
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            signInErrorMessage = "Apple 登录暂时没有完成，请再试一次。"
        }
    }
}

private struct OnboardingBundleImage: View {
    let filename: String
    let size: CGSize

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var resolvedImage: UIImage? {
        if let image = UIImage(named: filename) {
            return image
        }
        if let url = Bundle.main.url(forResource: filename, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        #if DEBUG
        let previewPath = "/Users/xinyuewang/BolaBola/BolaBola iOS/\(filename).png"
        if let image = UIImage(contentsOfFile: previewPath) {
            return image
        }
        #endif
        return nil
    }
}

private struct IntroCompanionPage: View {
    let isActive: Bool
    let onContinue: () -> Void
    @State private var entrancePhase = 0
    @State private var entranceRunID = 0

    var body: some View {
        OnboardingScreen(primaryTitle: "继续", primaryAction: onContinue) {
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingBundleImage(
                        filename: "OnboardingIntroHi",
                        size: CGSize(width: 65, height: 42)
                    )
                        .padding(.top, 18)
                        .introEntrance(active: entrancePhase >= 1)
                        .offset(x: 2)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("我是")
                            .font(.system(size: 20, weight: .regular))
                        Text("Bola")
                            .font(.system(size: 30, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                        .padding(.top, 8)
                        .introEntrance(active: entrancePhase >= 2)
                        .offset(x: 2)

                    OnboardingBundleImage(
                        filename: "OnboardingIntroNameUnderline",
                        size: CGSize(width: 105, height: 5)
                    )
                    .padding(.top, -2)
                    .introEntrance(active: entrancePhase >= 3)
                    .offset(x: 2)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("我来自一个和你有点不一样的世界。")
                            .introEntrance(active: entrancePhase >= 4, response: 1.85)
                        Text("现在，我会陪在你身边。")
                            .introEntrance(active: entrancePhase >= 5, response: 1.85)
                        Text("如果你愿意，我会一点点了解你。")
                            .introEntrance(active: entrancePhase >= 6, response: 1.85)
                    }
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.black.opacity(0.9))
                        .padding(.top, 17)
                        .offset(x: 2)

                    VStack(alignment: .leading, spacing: 18) {
                        IntroFeatureRow(
                            imageName: "OnboardingIntroFeatureHearts",
                            imageSize: CGSize(width: 26, height: 26),
                            title: "我会陪伴你",
                            detail: "和你互动，慢慢熟悉，记住你的喜好"
                        )
                        IntroFeatureRow(
                            imageName: "OnboardingIntroFeatureSoil",
                            imageSize: CGSize(width: 28.5, height: 28.5),
                            title: "我会慢慢成长",
                            detail: "每次陪伴都会让我变得不一样"
                        )
                        IntroFeatureRow(
                            imageName: "OnboardingIntroFeatureEdit",
                            imageSize: CGSize(width: 31, height: 25.5),
                            title: "我会记住关于你的一切",
                            detail: "一起生活的那些日常，都会成为我们的记忆"
                        )
                    }
                    .padding(.top, 28)
                    .introEntrance(active: entrancePhase >= 7)
                    .offset(x: 2)

                    Spacer(minLength: 250)
                }

                OnboardingBundleImage(
                    filename: "OnboardingIntroSlime",
                    size: CGSize(width: 378, height: 271)
                )
                .frame(maxWidth: .infinity)
                .offset(y: -25)
                .introEntrance(active: entrancePhase >= 8)
            }
            .frame(minHeight: 690, alignment: .top)
            .onAppear {
                if isActive {
                    replayEntrance(after: 0.28)
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    replayEntrance(after: 0.28)
                } else {
                    resetEntrance()
                }
            }
        }
    }

    private func replayEntrance(after delay: TimeInterval) {
        resetEntrance()
        let runID = entranceRunID
        let steps: [(Int, TimeInterval)] = [
            (1, 0.08),
            (2, 0.3),
            (3, 0.36),
            (4, 1.31),
            (5, 2.09),
            (6, 2.83),
            (7, 3.75),
            (8, 3.93)
        ]
        for (phase, phaseDelay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + phaseDelay) {
                guard entranceRunID == runID, isActive else { return }
                entrancePhase = max(entrancePhase, phase)
            }
        }
    }

    private func resetEntrance() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            entranceRunID += 1
            entrancePhase = 0
        }
    }
}

private extension View {
    func introEntrance(active: Bool, response: Double = 0.86) -> some View {
        opacity(active ? 1 : 0)
            .offset(y: active ? 0 : 10)
            .animation(.spring(response: response, dampingFraction: 0.94), value: active)
    }
}

private struct LevelUpPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("多和 Bola 互动来提升")
                            .font(.system(size: 32.5, weight: .regular))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 28)
                            .padding(.top, 36)
                            .onboardingBlockEntrance(isActive: isActive, index: 0)

                        Image("OnboardingLevelUpHero")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, -w * 0.10)
                            .padding(.top, -w * 0.32)
                            .padding(.bottom, -w * 0.30 + 25)
                            .onboardingBlockEntrance(isActive: isActive, index: 1)

                        VStack(alignment: .leading, spacing: 20) {
                            MetricExplainRow(
                                imageName: "OnboardingLevelUpStairs",
                                title: "成长值",
                                detail: "通过完成任务和日常互动获得，用于提升\nBola 的成长等级。"
                            )
                            MetricExplainRow(
                                imageName: "OnboardingLevelUpHeart",
                                title: "陪伴值",
                                detail: "平时与 Bola 的陪伴时间越长，数值越高。",
                                iconSize: 52,
                                iconOffsetY: -8
                            )
                        }
                        .padding(.horizontal, 28)
                        .padding(.leading, 15)
                        .padding(.top, 16)
                        .onboardingBlockEntrance(isActive: isActive, index: 2)
                    }
                    .padding(.bottom, 28)
                }
                .scrollDisabled(true)
                .overlay(alignment: .bottom) {
                    GrowingBars()
                        .allowsHitTesting(false)
                        .onboardingBlockEntrance(isActive: isActive, index: 3)
                }

                Button(action: onContinue) {
                    Text("继续")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BolaTheme.onAccentForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(BolaTheme.accent)
                        .clipShape(Capsule())
                }
                .onboardingBlockEntrance(isActive: isActive, index: 4)
                .padding(.horizontal, 36)
                .padding(.bottom, 18)
            }
        }
    }
}

private struct NotificationPermissionPage: View {
    let isActive: Bool
    let status: UNAuthorizationStatus
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingScreen(
            isActive: isActive,
            primaryTitle: status == .authorized ? "继续" : "允许通知",
            primaryAction: onAllow,
            secondaryTitle: "跳过",
            secondaryAction: onSkip
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让 Bola 更好的陪伴你")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)
                    .onboardingBlockEntrance(isActive: isActive, index: 0)

                Text("允许 BolaBola 发送通知，更好的了解你的健康数据")
                    .font(.system(size: 12.3, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.34))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                    .onboardingBlockEntrance(isActive: isActive, index: 1)

                NotificationPlaceholderCard()
                    .padding(.top, 34)
                    .onboardingBlockEntrance(isActive: isActive, index: 2)

                OnboardingBundleImage(
                    filename: "OnboardingNotificationHero",
                    size: CGSize(width: 220, height: 220)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, -28)
                .padding(.top, 26)
                .onboardingBlockEntrance(isActive: isActive, index: 3)
            }
        }
    }
}

private struct HealthRhythmPage: View {
    let isActive: Bool
    let requested: Bool
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(
            isActive: isActive,
            primaryTitle: requested ? "继续" : "继续",
            primaryAction: onContinue
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bola 正在感知你的状态")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)
                    .onboardingBlockEntrance(isActive: isActive, index: 0)

                Text("通过 HRV（心率变异性），Bola 会感知你现在的状态")
                    .font(.system(size: 12.3, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.34))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                    .onboardingBlockEntrance(isActive: isActive, index: 1)

                HStack {
                    Spacer(minLength: 0)
                    RhythmArcShowcase()
                    Spacer(minLength: 0)
                }
                .padding(.top, 24)
                .onboardingBlockEntrance(isActive: isActive, index: 2)

                HStack {
                    Spacer(minLength: 0)
                    RhythmLegendGrid()
                        .frame(width: 260)
                    Spacer(minLength: 0)
                }
                .padding(.top, 75)
                .onboardingBlockEntrance(isActive: isActive, index: 3)
            }
        }
    }
}

private struct QuestionIntroPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(isActive: isActive, primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("最后\n还有一些简单的问题")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .lineSpacing(6)
                    .padding(.top, 20)
                    .padding(.leading, 30)
                    .onboardingBlockEntrance(isActive: isActive, index: 0)

                HStack {
                    Spacer()
                    QuestionBoxHero()
                        .frame(width: 220, height: 250)
                        .padding(.top, 66)
                    Spacer()
                }
                .onboardingBlockEntrance(isActive: isActive, index: 1)
            }
        }
    }
}

private struct UserNicknamePage: View {
    let isActive: Bool
    @Binding var nickname: String
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(
            isActive: isActive,
            animateEntrance: false,
            scrollsWithKeyboard: true,
            primaryTitle: "继续",
            primaryAction: onContinue
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让我更了解一下你吧")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)

                QuestionStickerRow(bubble: "我该如何称呼你呢")
                .padding(.top, 34)

                RoundedTextField(text: $nickname, placeholder: "输入你的名字或昵称")
                    .padding(.top, 20)
            }
        }
    }
}

private struct BirthdayPage: View {
    let isActive: Bool
    @Binding var birthDate: Date
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(isActive: isActive, animateEntrance: false, primaryTitle: "继续", primaryAction: onContinue) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让我更了解一下你吧")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)

                QuestionStickerRow(bubble: "请问你的生日是？")
                .padding(.top, 34)

                BirthdayPickerCard(birthDate: $birthDate)
                    .padding(.top, 20)
            }
        }
    }
}

private struct GenderPage: View {
    let isActive: Bool
    @Binding var selectedGender: OnboardingGender?
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(
            isActive: isActive,
            animateEntrance: false,
            primaryTitle: "继续",
            primaryAction: onContinue
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让我更了解一下你吧")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)

                QuestionStickerRow(bubble: "请问你的性别是？")
                .padding(.top, 34)

                VStack(spacing: 14) {
                    ForEach(OnboardingGender.allCases) { option in
                        Button {
                            selectedGender = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.88))
                                Spacer()
                                if selectedGender == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(BolaTheme.accent)
                                }
                            }
                            .padding(.horizontal, 24)
                            .frame(height: 60)
                            .background(Color.white.opacity(selectedGender == option ? 0.96 : 0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                    }
                }
                .padding(.top, 94)
            }
        }
    }
}

private struct BolaNicknamePage: View {
    let isActive: Bool
    @Binding var nickname: String
    let onContinue: () -> Void

    var body: some View {
        OnboardingScreen(
            isActive: isActive,
            animateEntrance: false,
            scrollsWithKeyboard: true,
            primaryTitle: "继续",
            primaryAction: onContinue
        ) {
            VStack(alignment: .center, spacing: 0) {
                Text("给 Bola 起个专属名称吧")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)

                Text("它会记住这个名字哦")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 34)

                ClearableRoundedField(text: $nickname, placeholder: "比如：波拉 / 小黑 / Bobo")
                    .padding(.top, 44)

                GlowingMascotCard()
                    .frame(width: 260, height: 230)
                    .padding(.top, 58)
            }
        }
    }
}

private struct ReadyPage: View {
    let isActive: Bool
    let onEnter: () -> Void

    var body: some View {
        OnboardingScreen(isActive: isActive, primaryTitle: "进入 Bola 的空间", primaryAction: onEnter) {
            VStack(alignment: .leading, spacing: 0) {
                Text("一切准备就绪！")
                    .font(.system(size: 32.5, weight: .regular))
                    .foregroundStyle(.black)
                    .padding(.top, 108)
                    .onboardingBlockEntrance(isActive: isActive, index: 0)

                HStack {
                    Spacer()
                    ReadyHeroScene()
                        .frame(width: 320, height: 300)
                        .padding(.top, 66)
                    Spacer()
                }
                .onboardingBlockEntrance(isActive: isActive, index: 1)
            }
        }
    }
}

private struct IntroFeatureRow: View {
    let imageName: String
    let imageSize: CGSize
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            OnboardingBundleImage(filename: imageName, size: imageSize)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18.8, weight: .bold))
                    .foregroundStyle(Color(red: 0xC0 / 255, green: 0xE1 / 255, blue: 0))
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
        }
    }
}

private struct MetricExplainRow: View {
    let imageName: String
    let title: String
    let detail: String
    var iconSize: CGFloat = 42
    var iconOffsetY: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .offset(y: iconOffsetY)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.black)
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GrowingBars: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach([0.48, 0.68, 0.86], id: \.self) { value in
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BolaTheme.accent.opacity(0.06), BolaTheme.accent.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 82, height: 220 * value)
            }
        }
        .frame(height: 220, alignment: .bottom)
    }
}

private struct NotificationPlaceholderCard: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .frame(height: 72)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 290, height: 34)
                .offset(y: -10)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 250, height: 30)
                .offset(y: -16)
        }
    }
}

private struct RhythmArcShowcase: View {
    var body: some View {
        ZStack {
            ZStack {
                ArcShape()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.98, green: 0.61, blue: 0.12),
                                Color(red: 1.0, green: 0.87, blue: 0.12),
                                Color(red: 0.58, green: 0.95, blue: 0.32),
                                Color(red: 0.42, green: 0.9, blue: 0.75)
                            ],
                            center: .center,
                            startAngle: .degrees(180),
                            endAngle: .degrees(0)
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 330, height: 180)

                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .offset(y: -76)
            }

            Image("GrowthHeroIsland")
                .resizable()
                .scaledToFit()
                .frame(width: 224)
                .offset(x: 10, y: 42)
        }
    }
}

private struct RhythmLegendGrid: View {
    private let items: [(Color, String)] = [
        (Color(red: 1.0, green: 0.87, blue: 0.12), "节奏起伏"),
        (Color(red: 0.58, green: 0.95, blue: 0.32), "节奏平稳"),
        (Color(red: 0.98, green: 0.61, blue: 0.12), "节奏不稳"),
        (Color(red: 0.42, green: 0.9, blue: 0.75), "节奏满满"),
    ]

    var body: some View {
        VStack(spacing: 22) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                HStack(spacing: 26) {
                    legendItem(items[i])
                    legendItem(items[i + 1])
                }
            }
        }
    }

    private func legendItem(_ item: (Color, String)) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.0)
                .frame(width: 20, height: 20)
            Text(item.1)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.56))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

private struct QuestionBoxHero: View {
    var body: some View {
        OnboardingBundleImage(
            filename: "OnboardingQuestionHero",
            size: CGSize(width: 260, height: 260)
        )
    }
}

private struct BolaChatBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.black.opacity(0.88))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Color(uiColor: .systemBackground).opacity(0.88),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.74), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
    }
}

private struct QuestionStickerRow: View {
    let bubble: String

    var body: some View {
        OnboardingBundleImage(
            filename: "OnboardingQuestionSticker",
            size: CGSize(width: 200, height: 200)
        )
        .overlay(alignment: .topLeading) {
            BolaChatBubble(text: bubble)
                .fixedSize()
                .offset(x: -140, y: -10)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, -28)
        .padding(.top, 34)
    }
}

private struct RoundedTextField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .frame(height: 60)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
    }
}

private struct BirthdayPickerCard: View {
    @Binding var birthDate: Date

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("", selection: $birthDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 190)

            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: 32,
                    bottomTrailing: 32,
                    topTrailing: 0
                ),
                style: .continuous
            )
                .fill(Color.white.opacity(0.92))
                .frame(height: 34)
                .overlay {
                    Text(formattedDate)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.46))
                }
        }
        .background(Color.black.opacity(0.06))
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .mask(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: birthDate)
    }
}

private struct ClearableRoundedField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.black)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.black.opacity(0.2))
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(Color.white.opacity(0.88))
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

private struct GlowingMascotCard: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BolaTheme.accent.opacity(0.85), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 106
                    )
                )
                .frame(width: 220, height: 220)
            Image("sticker_gathxr")
                .resizable()
                .scaledToFit()
                .frame(width: 188)
        }
    }
}

private struct ReadyHeroScene: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BolaTheme.accent.opacity(0.52), Color.clear],
                        center: .center,
                        startRadius: 24,
                        endRadius: 150
                    )
                )
                .frame(width: 280, height: 280)

            Image("WatchS10Full")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
                .offset(x: -88, y: 18)

            TriangleBeam()
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.35), BolaTheme.accent.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 160, height: 130)
                .rotationEffect(.degrees(-10))
                .offset(x: -12, y: 2)

            Image("sticker_gathxr")
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .offset(x: 84, y: 0)
        }
    }
}

private struct TriangleBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 18, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct HeroHalfDome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            HalfCircle()
                .fill(
                    LinearGradient(
                        colors: [
                            BolaTheme.accent.opacity(0.12),
                            BolaTheme.accent.opacity(0.42)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    ZStack {
                        sparkle(offsetX: -96, offsetY: 58, size: 18)
                        sparkle(offsetX: -24, offsetY: 24, size: 14)
                        sparkle(offsetX: 82, offsetY: 62, size: 16)
                        sparkle(offsetX: 132, offsetY: 76, size: 26)
                    }
                }

            content
        }
        .frame(height: 270)
    }

    private func sparkle(offsetX: CGFloat, offsetY: CGFloat, size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: offsetX, y: offsetY)
    }
}

private struct HalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("Onboarding") {
    IOSOnboardingView {}
}
#endif
