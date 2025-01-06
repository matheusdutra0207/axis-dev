import sys
import cv2
import numpy as np

# Versão do Python
python_version = sys.version

# Versão do OpenCV
opencv_version = cv2.__version__

# Versão do NumPy
numpy_version = np.__version__

print(f"Versão do Python: {python_version}")
print(f"Versão do OpenCV: {opencv_version}")
print(f"Versão do NumPy: {numpy_version}")
