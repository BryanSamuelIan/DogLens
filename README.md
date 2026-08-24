# 🐶 DogLens

**DogLens** is an iOS dog breed detection app built with **SwiftUI** and **Core ML**. The app uses a computer vision object detection model to detect dogs in images, identify their breeds, and show where each dog is located in the image.

Users can either take a photo directly using the in-app camera or select an existing image from their photo library. After the image is processed, DogLens displays the detected dogs with their bounding boxes, breed names, and confidence scores.

Detected dog images can also be saved to the device's photo library and organized into breed-specific galleries using **SwiftData**.

## ✨ Features

* 📷 **Scan with Camera**

  * Take a photo directly inside the app.
  * Process the captured image using Core ML.

* 🖼️ **Upload from Photo Library**

  * Select an existing image using the system photo picker.
  * Process the selected image locally on the device.

* 🐕 **Multiple Dog Detection**

  * Detect multiple dogs in a single image.
  * Determine the location of each dog using bounding boxes.
  * Count the number of detected dogs.

* 🏷️ **Dog Breed Recognition**

  * Identify the breed of each detected dog.
  * Currently supports **52 dog breed classes**.

* 📊 **Detection Results**

  * Display the inference result with bounding boxes.
  * Show detected breed names.
  * Show confidence scores.
  * Show the total number of detected dogs.

* 💾 **Save Detection Results**

  * Save annotated inference images to the device's photo library.

* 🗂️ **Breed Gallery**

  * Store detected dog images using SwiftData.
  * Organize images by breed.
  * View the detection count for each breed.
  * Browse images associated with each detected breed.

## 🧠 How It Works

DogLens processes an image through the following pipeline:

```text
Camera / Photo Library
        ↓
     Input Image
        ↓
     Core ML Model
        ↓
  Object Detection
        ↓
 ┌──────┴────────┐
 ↓               ↓
Dog Location   Dog Breed
 ↓               ↓
Bounding Box   Class ID
        ↓
 Detection Result
        ↓
 ┌──────┴─────────────┐
 ↓                    ↓
Save to Photos     SwiftData
                       ↓
                 Breed Gallery
```

The Core ML model detects individual dogs and returns information such as:

* Bounding box
* Class ID
* Confidence score

The class ID is then mapped to one of DogLens' supported dog breeds.

## 🐕 Supported Breeds

DogLens currently supports **52 breeds**:

1. Afghan Hound
2. Bernese Mountain Dog
3. Border Collie
4. Border Terrier
5. Chihuahua
6. Doberman
7. French Bulldog
8. German Shepherd
9. Great Dane
10. Greater Swiss Mountain Dog
11. Italian Greyhound
12. Labrador Retriever
13. Maltese Dog
14. Mexican Hairless
15. Newfoundland
16. Norfolk Terrier
17. Norwegian Elkhound
18. Old English Sheepdog
19. Pekingese
20. Pembroke
21. Pomeranian
22. Rottweiler
23. Saint Bernard
24. Samoyed
25. Scottish Deerhound
26. Shih-Tzu
27. Siberian Husky
28. Staffordshire Bull Terrier
29. Tibetan Mastiff
30. Yorkshire Terrier
31. Basset
32. Beagle
33. Bloodhound
34. Borzoi
35. Boxer
36. Bull Mastiff
37. Chow
38. Cocker Spaniel
39. Collie
40. Golden Retriever
41. Malamute
42. Malinois
43. Miniature Pinscher
44. Miniature Poodle
45. Miniature Schnauzer
46. Papillon
47. Pug
48. Standard Poodle
49. Standard Schnauzer
50. Toy Poodle
51. Toy Terrier
52. Wire-haired Fox Terrier

## 🛠️ Technology Stack

| Technology       | Purpose                              |
| ---------------- | ------------------------------------ |
| **SwiftUI**      | User interface                       |
| **Core ML**      | On-device machine learning inference |
| **YOLO**         | Object detection model               |
| **SwiftData**    | Local persistence and breed gallery  |
| **AVFoundation** | Camera capture                       |
| **PhotosUI**     | Photo library selection              |
| **PhotoKit**     | Saving images to Photos              |
| **Git**          | Version control                      |
| **Xcode Cloud**  | CI/CD and automated builds           |
