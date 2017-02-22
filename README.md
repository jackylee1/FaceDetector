![image](/logo.png?raw=true)

# Face Detector Surveillance App

The goal of this project was to create an app that could be integrated within the DJI Go app to perform surveillance in a set area or on a set waypoint. The app uses the Camera to detect faces and upon detecting one, a photo of the person (or intruder) is captured. As soon as this event is triggered, the captured photo is uploaded to my Amazon S3 bucket, at the same time, a POST request is sent to my Python web server that I am hosting on Heruko, to send an SMS with details of the event to my phone. I am using Amazon Cognito Unauthenticated role. With a small change, you could use your Twitter, Facebook, or Google account to authenticate with Amazon Web Services. I focused on creating a rich app by leveraging cloud services for backend, cutting edge libraries for face detection, and iPhone’s own modern libraries.

## Dependencies
* Google Mobile Vision Framework
* Amazon AWS Framework

## Web Services Used
* Core Location
* AVFoundation

## Future Improvemenets
I tried to build an app that would bring about a new idea and that is also along the line of my research and advancements in the Augmented Reality and Artificial Intelligence fields. I plan on implementing the face detection using TensorFlow to be able to recognize people’s faces.

## Shortcomings
* In this project, I focued on the logic and integration of different components and I did not spend much time on the User Interface and the overal User Experience.


