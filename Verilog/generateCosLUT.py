# -*- coding: utf-8 -*-
"""
Created on Fri Nov 15 16:32:12 2019

@author: cnorf
"""
import numpy as np
import matplotlib.pyplot as plt

N = (2**12) # number of points per wave
plotStuff = 0

if(plotStuff):
    fig, ax = plt.subplots(1,1)
    ax.grid()

# show a cosine for reference
if(plotStuff):
    x = np.arange(0,2*np.pi,0.1) # start,stop,step
    y = np.cos(x)
    x = x * N / (2 * np.pi) - 1/2
    plt.plot(x,y,'-r')

# generate the LUT
with open("LUTcos.txt", "w") as text_file:
    n = 0
    while(n < N):
        cosVal = np.cos(np.pi*(2*n+1)/N) # 2pi * (2n+1)/2N
        #print("{}: {}".format(n, cosVal))
        if(n<N/4):
            if(plotStuff):
                ax.plot(n, cosVal, 'bo')
            binaryCosVal = "{0:08b}".format(int(round(cosVal*(2**8))))
            if(int(round(cosVal*(2**8))) == 2**8):
                binaryCosVal = "11111111"
            print("{0}    //{1}: {2}".format(binaryCosVal, n, cosVal), file=text_file)
        else:
            if(plotStuff):
                ax.plot(n, cosVal, 'mo')
        n = n + 1
