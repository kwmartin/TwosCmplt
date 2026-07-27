# anal_functs.py
#
# This script is primarilly intended to be a utility app to analyze impulse responses
# by plotting the magnitude response of FFTs.
#
# At this time, the script is working but very rough. There is a lot of extraneous routines, imports, etc.
# that were used during development and trying differenet alternatives. These will be removed
# in the future, but this has not happened yet. For the curious, they might be of minor interest? For example,
# fltrAllPass() can be used to obtain a 90 degree phase shift in a positive pass filter, to isolate the positive
# frequency component of a cisoid (this is completely tangent to using this app in analyzing impulse responses).
# Also, we have not yet decided whether to use matplotlib or pyqtgraph? Currently, we are using
# matplotlib because of the ease of saving to a *.png file (right most icon).
#
# Notes: 1) If there are broad skirts, you have not analyzed an exact integer of periods of the input signal.
#        2) If you see the output at 0 is an anomoly, it is due to a dc offset.
#        3) I think the file IO stuff, might be useful for others as an example, especially np.genfromtxt(), and
#           from scipy.io import savemat
#
# Summary: save this somewhere if you are into complex signal processing; when I clean it, everything
# extraneous will be deleted.
#

import sys, os
import numpy as np
from cmath import *
from math import *
from scipy.signal import *
from string import Template
from scipy.io import savemat
from io import StringIO
from scipy import io, integrate, linalg, signal
from scipy.sparse.linalg import cg, eigs
import inspect
import argparse
import textwrap
from time import sleep
import subprocess
from pathlib import Path

import matplotlib

# matplotlib.use("TkAgg")
import matplotlib.pyplot as plt  # matplotlib.use('TkAgg')

import pyqtgraph as pg
from pyqtgraph.Qt import QtCore
import pyqtgraph.multiprocess as mp

proc = mp.QtProcess(processRequests=False)
rpg = proc._import("pyqtgraph")
app = rpg.mkQApp("PyQtGraph Plot")
win = None
qtplt = None

import trace

hx2byts = lambda hx: bytes.fromhex(hx)
byts2hx = lambda byts: bytes.hex(byts)
str2byts = lambda str: str.encode("utf_8")
byts2str = lambda byts: byts.decode("utf-8")
rnPrcs = lambda args: subprocess.run(
    args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
)
rnPrcsOut = lambda args: byts2str(
    subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout,
    timeout=60,
)
pltCoid = lambda coid: drwPlt(coid.real, coid.imag)


def trnc(dat, per):
    np = per * int(len(dat) / per)
    return dat[-np:]


def applyTmplt(str, dct, strip=False):
    rtrnStr = Template(str).substitute(dct)
    if strip:
        rtrnStr = rtrnStr.rstrip()
    return rtrnStr


def hermition(A, **kwargs):
    return np.conj(A, **kwargs).T


H = hermition


def trace_main():
    # create a Trace object, telling it what to ignore, and whether to
    # do tracing or line-counting or both.
    tracer = trace.Trace(ignoredirs=[sys.prefix, sys.exec_prefix], trace=0, count=1)

    # run the new command using the given tracer
    tracer.run("main()")

    # make a report, placing output in the current directory
    r = tracer.results()
    r.write_results(show_missing=True, coverdir=".")


def get_file_data(fileNm: str, columns: list, nmb2skip=0):
    with open(fileNm, "r") as flPt:
        clmns = tuple(range(len(columns)))
        dat = flPt.read()
        inDat = np.genfromtxt(StringIO(dat), usecols=clmns, skip_header=nmb2skip)
        inpDat = {}
        for i, clmn in enumerate(columns):
            try:
                if inDat.ndim == 2:
                    inpDat[clmn] = inDat[:, clmns[i]]
                else:
                    inpDat[clmn] = inDat[:]
            except:
                print(f"Error reading data from {fileNm}")
    return inpDat


def get_real_data(fileNm: str, columns: list, nmb2skip=0):
    with open(fileNm, "r") as flPt:
        clmns = tuple(range(len(columns)))
        dat = flPt.read()
        inDat = np.genfromtxt(StringIO(dat), usecols=clmns, skip_header=nmb2skip)
        inpDat = {}
        for i, clmn in enumerate(columns):
            try:
                if inDat.ndim == 2:
                    inpDat[clmn] = inDat[:, clmns[i]]
                else:
                    inpDat[clmn] = inDat[:]
            except:
                print(f"Error reading data from {fileNm}")
    return inpDat


def move_figure(f, x, y):
    """Move figure's upper left corner to pixel (x, y)"""
    backend = matplotlib.get_backend()
    if backend == "TkAgg":
        f.canvas.manager.window.wm_geometry("+%d+%d" % (x, y))
    elif backend == "WXAgg":
        f.canvas.manager.window.SetPosition((x, y))
    else:
        # This works for QT and GTK
        # You can also use window.setGeometry
        f.canvas.manager.window.move(x, y)


def qtPlt(x=None, y=[], title="Magnitude Plot", xlim=None, ylim=None):
    global rpg, win, qtplt
    aa = 0
    if not isinstance(y, np.ndarray):
        ydat = np.array(y)
    else:
        ydat = y
    if x == []:
        xaxis = None
    else:
        xaxis = x

    rpg.setConfigOption("background", "w")
    rpg.setConfigOption("foreground", "b")
    rpg.mkPen(cosmetic=False, width=2.5, color="b")

    win = rpg.GraphicsLayoutWidget(show=True, title=title)
    win.resize(1000, 800)
    win.setWindowTitle(title)

    # Enable antialiasing for prettier plots
    rpg.setConfigOptions(antialias=True)

    colors = ["r", "b", "g", "y"]
    plt = win.addPlot()

    if ydat.ndim == 1:
        plt.plot(x=xaxis, y=ydat, pen="r")
    else:
        for i, y in enumerate(ydat):
            plt.plot(x=xaxis, y=y, pen=colors[i])

    plt.setLabel("left", "Magnitude")
    plt.setLabel("bottom", "Freq")

    if not ylim == None:
        plt.setYRange(ylim[0], ylim[1])

    if not xlim == None:
        plt.setXRange(xlim[0], xlim[1])

    return plt


def drwPlt(cs, sn):
    fig = plt.figure(figsize=(8, 6))
    move_figure(fig, 500, 200)
    n = np.size(sn)
    rng = np.arange(0, n)
    plt.plot(rng, sn, label="sine")
    plt.plot(rng, cs, label="cos")
    plt.title("Plot of Sine and Cosine Functions")
    plt.legend(loc="upper right", bbox_to_anchor=(1.0, 1.0))
    plt.show(block=True)
    a = 0


def pltArry(arry):
    fig = plt.figure(figsize=(8, 6))
    move_figure(fig, 500, 200)
    n = np.size(arry)
    rng = np.arange(0, n)
    plt.plot(rng, arry, label="Array")
    plt.title("Plot of Array")
    plt.legend(loc="upper right", bbox_to_anchor=(1.0, 1.0))
    plt.show(block=True)
    a = 0


def magFFT(vals, Nlen=False):
    N = len(vals)
    if Nlen == False:
        FFT = np.fft.fft(vals)
    else:
        N = Nlen
        FFT = np.fft.fft(vals, n=Nlen)

    AFFT = abs(FFT) / N
    AdB = 20.0 * np.log10(AFFT + 1e-60)
    xaxis = list(map(lambda x: float(x) / float(N), range(N)))
    return (xaxis, AdB)


def make_base_plot(xaxis, AdB, ylim=None, title=None, color="b"):
    fig, ax = plt.subplots(figsize=(10, 8))
    ax.plot(xaxis, AdB, color=color)
    ax.set_ylabel("Magnitude (dB)", fontsize=22)      # larger axis label
    ax.set_xlabel("Frequency", fontsize=22)      # larger axis label
    if title is not None:
        ax.set_title(title, fontsize=26)         # larger title

    if ylim is not None:
        ax.set_ylim(ylim)

    # Increase tick label font size (numbers on axes)
    ax.tick_params(axis='both', which='major', labelsize=20)

    # Reduce number of y-axis ticks (e.g., ~5 ticks)
    ax.locator_params(axis='y', nbins=6)

    return fig, ax

def add_curve(ax, xaxis2, AdB2, color="red", **plot_kwargs):
    ax.plot(xaxis2, AdB2, color=color, **plot_kwargs)


def on_key(event):
    # any key closes and lets the script finish
    plt.close(event.canvas.figure)


def close_on_key(event):
    if event.key == "q":  # or 'enter', 'escape', etc.
        plt.close(event.canvas.figure)


def datPlt(data, ylim=None, title=None, ax=None, color="r"):
    N = len(data)

    if ax is None:
        fig, ax = plt.subplots(figsize=(10, 8))
        ax.plot(data, color=color)
        if not ylim is None:
            ax.set_ylim(ylim)
        if not title is None:
            ax.set_title(title)
        move_figure(fig, 700, 400)
        return fig, ax
    else:
        ax.plot(data, color=color)
        return ax


def fftPlt(
    vals, ylim=[-80, 1], Nlen=False, title=None, Offset=False, ax=None, color="r"
):
    if Offset:
        vals = vals - vals[-1]

    N = len(vals)

    if Nlen == False:
        FFT = np.fft.fft(vals)
    else:
        N = Nlen
        FFT = np.fft.fft(vals, n=Nlen)

    AFFT = abs(FFT) / N
    AdB = 20.0 * np.log10(AFFT + 1e-60)
    xaxis = list(map(lambda x: float(x) / float(N), range(N)))

    # plt.ion()               # turn on interactive mode

    if ax is None:
        fig, ax = make_base_plot(xaxis, AdB, ylim, title, color="b")
        move_figure(fig, 500, 200)
        return fig, ax
    else:
        ax.plot(xaxis, AdB, color=color)
        return ax
    # plt.draw()
    # plt.pause(0.001)

    # plt.savefig("/home/Dropbox/programming/Python/cmplxApprx/figs/FFT.pdf")
    # plt.savefig("/home/Dropbox/programming/Python/cmplxApprx/figs/FFT.png")


def fltrAllPass(fpT, data):
    wpT = 2 * tan(pi * fpT)
    K = (1 - 2 / wpT) / (1 + 2 / wpT)
    A = [1, K]
    B = [K, 1]
    y = lfilter(B, A, data)
    return y


def anal_cis(file_nm, per):
    inDat = get_file_data(file_nm, ["cos", "sin"], nmb2skip=11)
    cs = trnc(inDat["cos"], per)
    sn = trnc(inDat["sin"], per)

    cmplxOid = cs + 1.0j * sn

    # specify number of signal periods in FFT so it is exactly periodic
    NPER = 256
    dB_min = -10
    fig, ax = fftPlt(
        cmplxOid, ylim=[dB_min, 130], Nlen=per * NPER, title="FFT Magnitude"
    )

    (xaxis, absFFT) = magFFT(cmplxOid)
    qtplt = qtPlt(x=xaxis, y=absFFT, title="Magnitude FFT", ylim=[dB_min, 130])

    savemat("inDat.mat", inDat)

    while 1:
        sleep(0.1)

    aa = 0


def data_plot(file_nms):
    file_nm = file_nms[0]
    path = Path(file_nm)
    with path.open() as f:
        first_ln = f.readline().strip()
        n_cols = len(first_ln.split())

    if n_cols == 2:
        inDat = get_real_data(file_nm, ["X", "Y"], nmb2skip=0)
        dat1 = inDat["X"]
        dat2 = inDat["Y"]

        fig, ax = datPlt(dat1, color="b")
        ax = datPlt(dat2, color='r', ax=ax)

    elif n_cols == 1:
        inDat = get_real_data(file_nm, ["X"], nmb2skip=0)
        dat = inDat["X"]

        fig, ax = datPlt(dat)

    if len(file_nms) > 1:
        colors = ["r", "g", "m", "c"]
        for i in range(1, len(file_nms)):
            file_nm = file_nms[i]
            path = Path(file_nm)
            with path.open() as f:
                first_ln = f.readline().strip()
                n_cols = len(first_ln.split())

            if n_cols == 2:
                inDat2 = get_real_data(file_nm, ["X", "Y"], nmb2skip=0)
                dat3 = inDat2["X"]
                dat4 = inDat2["Y"]

                ax = datPlt(dat3, color="g", ax=ax)
                ax = datPlt(dat4, color='m', ax=ax)

            elif n_cols == 1:
                inDat3 = get_real_data(file_nm, ["X"], nmb2skip=0)
                dat5 = inDat3["X"]

                fig, ax = datPlt(dat5, color="w", ax=ax)

    fig.canvas.mpl_connect("key_press_event", close_on_key)
    plt.show()
    aa = 0


def cmplx_plot(file_nms, per, lims):
    file_nm = file_nms[0]
    path = Path(file_nm)
    with path.open() as f:
        first_ln = f.readline().strip()
        n_cols = len(first_ln.split())

    if n_cols == 2:
        inDat = get_real_data(file_nm, ["X", "Y"], nmb2skip=0)
        cs = inDat["X"]
        sn = inDat["Y"]

        cmplxOid = cs + 1.0j * sn

        # specify number of signal periods in FFT so it is exactly periodic
        dat_len = len(cs)
        nlen = (dat_len // per) * per
        # NPER = 256
        # fig, ax = fftPlt(cmplxOid, ylim=lims, Nlen=per * NPER, title="FFT Magnitude")
        fig, ax = fftPlt(cmplxOid, ylim=lims, Nlen=nlen, title="FFT Magnitude")
    elif n_cols == 1:
        inDat = get_real_data(file_nm, ["X"], nmb2skip=0)
        dat = inDat["X"]
        dB_min = -30
        dB_max = 120

        # if plotting an impulse response, and there is an anomoly at dc, try setting
        # Offset=True. This assumes all data has an offset of the last element and removes
        # this offset.
        fig, ax = fftPlt(dat, ylim=lims, title="FFT Magnitude", Offset=False)

        aa = 0
    fig.canvas.mpl_connect("key_press_event", close_on_key)
    plt.show()
    aa=0


def filter_plot(file_nms, lims):
    file_nm = file_nms[0]
    path = Path(file_nm)
    with path.open() as f:
        first_ln = f.readline().strip()
        n_cols = len(first_ln.split())

    if n_cols == 2:
        inDat = get_real_data(file_nm, ["X", "Y"], nmb2skip=0)
        cs = inDat["X"]
        sn = inDat["Y"]

        cmplxOid = cs + 1.0j * sn

        fig, ax = fftPlt(cmplxOid, ylim=lims, title="FFT Magnitude", Offset=True)
    elif n_cols == 1:
        inDat = get_real_data(file_nm, ["X"], nmb2skip=0)
        dat = inDat["X"]

        # if plotting an impulse response, and there is an anomoly at dc, try setting
        # Offset=True. This assumes all data has an offset of the last element and removes
        # the offset.
        fig, ax = fftPlt(dat, ylim=lims, title="FFT Magnitude", Offset=False)

    if len(file_nms) > 1:
        colors = ["r", "g", "m", "c", "b", "crimson", "y"]
        for i in range(1, len(file_nms)):
            file_nm = file_nms[i]
            path = Path(file_nm)
            with path.open() as f:
                first_ln = f.readline().strip()
                n_cols = len(first_ln.split())

            if n_cols == 2:
                inDat = get_real_data(file_nm, ["X", "Y"], nmb2skip=0)
                cs = inDat["X"]
                sn = inDat["Y"]

                cmplxOid = cs + 1.0j * sn

                ax = fftPlt(
                    cmplxOid,
                    ylim=lims,
                    title="FFT Magnitude",
                    Offset=True,
                    ax=ax,
                    color=colors[i],
                )
            elif n_cols == 1:
                inDat = get_real_data(file_nm, ["X"], nmb2skip=0)
                dat = inDat["X"]

                # if plotting an impulse response, and there is an anomoly at dc, try setting
                # Offset=True. This assumes all data has an offset of the last element and removes
                # the offset.
                ax = fftPlt(
                    dat,
                    ylim=lims,
                    title="FFT Magnitude",
                    Offset=False,
                    ax=ax,
                    color=colors[i],
                )

    fig.canvas.mpl_connect("key_press_event", close_on_key)
    plt.show()

    # plt.pause(0.001)

    # plt.waitforbuttonpress()   # returns when input happens [web:83][web:89]
    # plt.close(fig)             # closes the window

    aa = 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description=textwrap.dedent(
            """\
          Analze a data signal using an FFT.
          The data file should be a column or columns
          generated by a simulation. If --period is not
          specified, it is assumed the data comes from an
          impulse response analysis of a filter. If --period
          is specified, (followed by the period), it is assumed
          the data is an integer number of periods from an oscillator.
        """
        ),
        formatter_class=argparse.RawTextHelpFormatter,
    )

    parser.add_argument(
        "file_nms",
        nargs="+",
        help=f"Specify the name of the data file",
    )

    parser.add_argument(
        "-p",
        "--period",
        type=int,
        default=None,
        help="Specify the period when the data input is periodic",
    )

    parser.add_argument(
        "-d",
        "--data",
        action="store_true",
        help="Specify -d to plot two data waveforms for comparison",
    )

    parser.add_argument(
        "-l",
        "--lims",
        nargs=2,
        type=int,
        metavar=("LOW", "HIGH"),
        default=None,
        help="Lower and upper limits in dB",
    )

    parser.add_argument(
        "-np",
        "--npers",
        type=int,
        default=None,
        help="number of periods to analyze using FFT",
    )

    args = parser.parse_args()
    if args.lims is not None:
        lims = args.lims
    else:
        lims = [-40, 60]

    if args.npers is not None:
        npers = args.npers
    else:
        npers = 1024

    if args.data == True:
        data_plot(args.file_nms)
    elif args.period is not None:
        cmplx_plot(args.file_nms, args.period, lims)
        # or we might want to change to
        # anal_cis(args.file_nm, args.period)
    else:
        filter_plot(args.file_nms, lims)
