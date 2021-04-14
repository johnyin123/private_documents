#!/usr/bin/env bash
apt -y install libsm6 libxext6 libxrender-dev python3 python3-pip cmake

mkdir ~/.pip/
echo -e "[global]\n" >~/.pip/pip.conf
# 替换PIP源 速度更快
echo -e "index-url = https://pypi.tuna.tsinghua.edu.cn/simple" >>~/.pip/pip.conf
echo -e "开始安装Python常见库"

python3.7 -m venv env
source env/bin/activate
python3.7 -m pip install --upgrade pip
python3.7 -m pip install numpy
python3.7 -m pip install pandas
python3.7 -m pip install matplotlib
python3.7 -m pip install sklearn
python3.7 -m pip install opencv-python
git clone https://github.com/davisking/dlib.git
DIR="$(pwd)"
mkidr -p ${DIR}/dlib/build
cd ${DIR}/dlib/build
cmake -H${DIR}/dlib -B${DIR}/dlib/build -DDLIB_USE_CUDA=1 -DUSE_AVX_INSTRUCTIONS=1
cd ${DIR}/dlib
cmake --build ./build
python3.7 setup.py install --yes USE_AVX_INSTRUCTIONS --yes DLIB_USE_CUDA
echo "check use cuda"
cat <<EOF
import dlib
print(dlib.__)
print(dlib.DLIB_USE_CUDA)
print(dlib.cuda.get_num_devices())
EOF
python3.7 -m pip install face_recognition

cat <<"EOF"
#!/usr/bin/env python3
# -*- coding: utf-8 -*- 
from __future__ import print_function
import dlib
import face_recognition
import cv2
import numpy as np

#print(dlib.__)
print(dlib.DLIB_USE_CUDA)
print(dlib.cuda.get_num_devices())


from PIL import Image, ImageDraw, ImageFont
def paint_chinese_opencv(im,chinese,pos,color):
    img_PIL = Image.fromarray(cv2.cvtColor(im,cv2.COLOR_BGR2RGB))
    font = ImageFont.truetype('NotoSansCJK-Regular.ttc',25)
    fillColor = color #(255,0,0)
    position = pos #(100,100)
    draw = ImageDraw.Draw(img_PIL)
    draw.text(position,chinese,font=font,fill=fillColor)
    img = cv2.cvtColor(np.asarray(img_PIL),cv2.COLOR_RGB2BGR)
    return img

# This is a super simple (but slow) example of running face recognition on live video from your webcam.
# There's a second example that's a little more complicated but runs faster.

# PLEASE NOTE: This example requires OpenCV (the `cv2` library) to be installed only to read from your webcam.
# OpenCV is *not* required to use the face_recognition library. It's only required if you want to run this
# specific demo. If you have trouble installing it, try any of the other demos that don't require it instead.

# Create arrays of known face encodings and their names
# Load a sample picture and learn how to recognize it.
known_face_encodings = [ ]
known_face_names = [ ]

known_face_names.append("johnyin")
face_encoding = face_recognition.face_encodings(face_recognition.load_image_file("johnyin.jpg"))[0]
known_face_encodings.append(face_encoding)

# Get a reference to webcam #0 (the default one)
video_capture = cv2.VideoCapture(0)
while True:
    # Grab a single frame of video
    ret, frame = video_capture.read()

    # Resize frame of video to 1/4 size for faster face recognition processing
    # small_frame = cv2.resize(frame, (0, 0), fx=0.25, fy=0.25)
    # rgb_frame = small_frame[:, :, ::-1]

    # Convert the image from BGR color (which OpenCV uses) to RGB color (which face_recognition uses)
    rgb_frame = frame[:, :, ::-1]

    # Find all the faces and face enqcodings in the frame of video
    face_locations = face_recognition.face_locations(rgb_frame)
    face_encodings = face_recognition.face_encodings(rgb_frame, face_locations)

    # Loop through each face in this frame of video
    for (top, right, bottom, left), face_encoding in zip(face_locations, face_encodings):
        # See if the face is a match for the known face(s)
        matches = face_recognition.compare_faces(known_face_encodings, face_encoding)

        name = "Unknown"

        # If a match was found in known_face_encodings, just use the first one.
        # if True in matches:
        #     first_match_index = matches.index(True)
        #     name = known_face_names[first_match_index]

        # Or instead, use the known face with the smallest distance to the new face
        face_distances = face_recognition.face_distance(known_face_encodings, face_encoding)
        best_match_index = np.argmin(face_distances)
        if matches[best_match_index]:
            name = known_face_names[best_match_index]
        print(u"found == > {}\n".format(name))
        # Draw a box around the face
        cv2.rectangle(frame, (left, top), (right, bottom), (0, 0, 255), 2)
        # Draw a label with a name below the face
        frame = paint_chinese_opencv(frame, name, (left + 6, bottom - 6), (255, 255, 255))
    # Display the resulting image
    cv2.imshow('Video', frame)

    # Hit 'q' on the keyboard to quit!
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# Release handle to the webcam
video_capture.release()
cv2.destroyAllWindows()
EOF
