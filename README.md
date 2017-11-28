# Glimmer--Brainwave entrainment and neurofeedback for Windows

Glimmer is a program for visual brainwave entrainment. It works to induce neural oscillations at a specific frequency by modulating the brightness of your monitor at that frequency, an approach that has shown promising results in modulating [memory](https://www.biorxiv.org/content/biorxiv/early/2017/10/15/191189.full.pdf) and [attention](http://journals.plos.org/plosone/article?id=10.1371/journal.pone.0143533) function, and [may be useful in reducing the buildup of Alzheimer's associated toxins in the brain](https://www.nature.com/articles/nature20587)

Glimmer is designed to provide brainwave entrainment "in the background" while you use your computer for other things. It can also be used in experiments to test the effects of entrainment applied at the same time participants complete cognitive tasks.

Glimmer can also provide neurofeedback and "closed-loop" entrainment (i.e. tuning the stimulation frequency to an individual's peak frequency) using data from a Neurosky Mindwave device and a Javascript-based scripting system.

## Getting Started

You can start Glimmer by running glimmer.exe from the "application.windows32" folder. The full-screen configuration menu should open immediatley. Select the frequency and amplitude you want, and click start. You can call up the settings screen at any time by holding your mouse in the bottom right corner of the screen.

If you want to use Glimmer with a Neurosky device, you will need to first (1) Pair the neurosky device with your computer, and (2) Acquire a script file that tells Glimmer how to process the EEG data (See the included scripting guide). Once both these components are in place, you can start the neurofeedback/closed loop mode using the "load script" button.

### Code

Glimmer is written using Processing 2.2.1 and depends on the Mindset Processing library for interfacing with Neurosky devices.

## License

This project is licensed under the Unlicense and is in the public domain (http://unlicense.org/)


## Acknowledgments

* Jorge Cardoso for developing the Neurosky interface library
* Kristian Kraljić for work on low-level mouse listeners in Java.