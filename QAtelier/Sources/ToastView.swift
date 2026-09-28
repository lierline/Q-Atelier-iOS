import UIKit

/// 안드로이드 Toast 와 같은 짧은 안내. 아래에 떴다가 3.5초 뒤 사라진다. 누르는 것을 막지 않는다
final class ToastView: UIView {
    private let label = UILabel()

    static func show(_ text: String, in host: UIView) {
        host.subviews.compactMap { $0 as? ToastView }.forEach { $0.removeFromSuperview() }
        let toast = ToastView(text: text)
        host.addSubview(toast)
        toast.translatesAutoresizingMaskIntoConstraints = false
        let guide = host.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            toast.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24),
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.2) { toast.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 3.5, options: [.allowUserInteraction]) {
            toast.alpha = 0
        } completion: { _ in
            toast.removeFromSuperview()
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private init(text: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(rgb: 0x1A1916).withAlphaComponent(0.94)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        label.text = text
        label.textColor = UIColor(rgb: 0xF2EEE6)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("코드로만 만든다")
    }
}
