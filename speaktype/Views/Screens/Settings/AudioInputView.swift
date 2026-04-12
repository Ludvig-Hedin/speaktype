import SwiftUI
import AVFoundation

struct AudioInputView: View {
    @StateObject private var audioRecorder = AudioRecordingService.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentPrimary)
                    
                    Text("Audio Input")
                        .font(Typography.displayLarge)
                        .foregroundStyle(Color.textPrimary)
                    
                    Text("Configure your microphone preferences")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                
                // Input Mode Section Removed

                    


                
                // Available Devices Section
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("Available Devices")
                            .font(Typography.headlineMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Button(action: {
                            audioRecorder.fetchAvailableDevices()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(Typography.bodySmall)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.border.opacity(0.4), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.stPlain)
                    }
                    
                    Text("Note: SpeakType will use the selected device for all recordings.")
                        .font(Typography.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                    
                    VStack(spacing: 12) {
                        if audioRecorder.availableDevices.isEmpty {
                            Text("No input devices found.")
                                .foregroundStyle(.gray)
                                .padding()
                        } else {
                            ForEach(audioRecorder.availableDevices, id: \.uniqueID) { device in
                                DeviceRow(
                                    name: device.localizedName,
                                    isActive: audioRecorder.isRecording
                                        && audioRecorder.selectedDeviceId == device.uniqueID,
                                    isSelected: audioRecorder.selectedDeviceId == device.uniqueID
                                )
                                .onTapGesture {
                                    audioRecorder.selectedDeviceId = device.uniqueID
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 40)
        }
        .background(Color.clear)
        .onAppear {
            audioRecorder.fetchAvailableDevices()
        }
    }
}



struct DeviceRow: View {
    let name: String
    let isActive: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentPrimary : Color.textMuted)
                .font(.title3)
            
            Text(name)
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
            
            Spacer()
            
            if isActive {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                    Text("Active")
                }
                .font(Typography.labelSmall)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentSuccess.opacity(0.15))
                .foregroundStyle(Color.accentSuccess)
                .clipShape(Capsule(style: .continuous))
            }
        }
        .padding(16)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Constants.UI.cardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: Constants.UI.cardCornerRadius, style: .continuous)
                    .fill((isSelected ? Color.bgSelected : Color.bgCard).opacity(0.72))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Constants.UI.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.textPrimary.opacity(0.18) : Color.border.opacity(0.45),
                    lineWidth: isSelected ? 1.25 : 1
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        .clickActionPointerCursor()
    }
}
