import SwiftUI

struct NoDetectionView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "questionmark.square.dashed")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundColor(.orange)
            
            Text("No Dogs Detected")
                .font(.title)
                .fontWeight(.bold)
            
            Text("We couldn't find any dogs in this image. Make sure the dog is clearly visible and try again.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                // Go back to the previous screen (Home)
                // For simplicity, we just dismiss
                dismiss()
            }) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NoDetectionView()
}
