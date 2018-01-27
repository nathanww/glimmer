# Glimmer--Brainwave entrainment and neurofeedback for Windows

Glimmer is a program for visual brainwave entrainment. It works to induce neural oscillations at a specific frequency by modulating the brightness of your monitor at that frequency, an approach that has shown promising results in modulating [memory](https://www.biorxiv.org/content/biorxiv/early/2017/10/15/191189.full.pdf) and [attention](http://journals.plos.org/plosone/article?id=10.1371/journal.pone.0143533) function, and [may be useful in reducing the buildup of Alzheimer's associated toxins in the brain](https://www.nature.com/articles/nature20587)

Glimmer is designed to provide brainwave entrainment "in the background" while you use your computer for other things. It can also be used in experiments to test the effects of entrainment applied at the same time participants complete cognitive tasks.

Glimmer can also provide neurofeedback and "closed-loop" entrainment (i.e. tuning the stimulation frequency to an individual's peak frequency) using data from a Neurosky Mindwave device and a Javascript-based scripting system.

## Getting Started

You can start Glimmer by running glimmer.exe from the "application.windows32" folder. The full-screen configuration menu should open immediatley. Select the frequency and amplitude you want, and click start. You can call up the settings screen at any time by holding your mouse in the bottom right corner of the screen.

### Neurofeedback and EEG 
Glimmer can use data from Mindwave Mobile and OpenBCI devices to provide neurofeedback and customize stimulation.

To use these features, you will need to acquire or write a script file that tells Glimmer how to process the EEG data (see the scripting guide), and then connect your EEG device and run the script.
##### Using an OpenBCI device
1. Connect the device to your computer and start the OpenBCI GUI.
2. Start the data stream
3. In the "networking" panel, set protocol to OSC, data type to "Time series", IP to 127.0.0.1, port to 12345, and address to /openbci. Click start.
4. Start Glimmer. It should say "EEG connected".
5. In Glimmer, select which OpenBCI channel you want to use for data (Glimmer only monitors one channel at a time)
6. Click "load script" and select your script file. The script will start automatically.

You can change the active channel at any time.

##### Using a Mindwave device
1. Make sure the MindWave is already paired to your computer's bluetooth and turned on. Also make sure that openBCI software is not running--if it is Glimmer will use this input instead of the Mindwave input
2. Start Glimmer and click the "load script" button.
3. Load your script file.
4. Glimmer will automatically connect to the MindWave and you should see "EEG connected" in a couple of seconds. Your script will start as soon as the Mindwave connects.


### Code

Glimmer is written using Processing 2.2.1 and depends on the Mindset Processing library for interfacing with Neurosky devices.

## License

This project is licensed under the Unlicense and is in the public domain (http://unlicense.org/)


## Acknowledgments

* Jorge Cardoso for developing the Neurosky interface library
* Kristian Kraljić for work on low-level mouse listeners in Java.# New Document