import oscP5.*;
import netP5.*;

import java.awt.MouseInfo;
import javax.script.ScriptEngine;
import javax.script.ScriptEngineManager; 
import ddf.minim.analysis.*;
import ddf.minim.*;
import processing.serial.*;
import pt.citar.diablu.processing.mindset.*;
import com.sun.jna.platform.WindowUtils;
import java.awt.*;
import java.awt.event.*;
import controlP5.*;
import com.sun.awt.AWTUtilities;
import lc.kra.system.mouse.GlobalMouseHook;
import lc.kra.system.mouse.event.GlobalMouseAdapter;
import lc.kra.system.mouse.event.GlobalMouseEvent;
OscP5 receiver; //for getting messages from openBCI
boolean hasOpenBCI=false; //is an OpenBCI system sending us messages?
int openBCIPointer=0; //pointer for the buffer
float[] openBCIBuffer; //put the openBCI data in two-second batches so it is compatible with what we get from neurosky
GlobalMouseHook mouseHook;
boolean overTaskbar=false;
int fakeRelease=0; //for some reason generating a mouse click requires multiple calls to Robot and that generates spurious release events. This is a counter of "fake" events.

int startFlickerTime=0;

float scriptAmplitude=0.5; //scaling value for script amplitude commands(1=script runs at double amplitude, 0.5=100% amplitude)
//are mouse buttons down?
boolean leftDown=false;
boolean rightDown=false;
boolean middleDown=false;
//functions available to scripts
String jsfunctions="function meanPower(dataIn,startFreq, endFreq) {  var startIndex=Math.round(startFreq / 0.1);  var endIndex=Math.round(endFreq / 0.1);  var total=0;  var count=0;  for (var i=startIndex; i<= endIndex; i++) {    total=total+dataIn[i];    count=count+1.0;  }  return total/count;}function maxFreq(dataIn,startFreq, endFreq) {  var startIndex=Math.round(startFreq / 0.1);  var endIndex=Math.round(endFreq / 0.1);  var highest=-1000;  var hi=-1;  for (var i=startIndex; i<= endIndex; i++) {    if (dataIn[i] > highest) {      highest=dataIn[i];      hi=(i*0.1)+0.1;    }  }  return hi;}function minFreq(dataIn,startFreq, endFreq) {  var startIndex=Math.round(startFreq / 0.1);  var endIndex=Math.round(endFreq / 0.1);  var lowest=1000;  var li=-1;  for (var i=startIndex; i<= endIndex; i++) {    if (dataIn[i] < lowest) {      lowest=dataIn[i];      li=(i*0.1)+0.1;    }  }  return li;} function centerOfGravity(dataIn,startFreq,endFreq) {  var startIndex=Math.round(startFreq / 0.1);  var endIndex=Math.round(endFreq / 0.1);  var total=0;  for (var i=startIndex; i<= endIndex; i++) {    total=total+dataIn[i];  }  var weighted=0;  var nSpan=endIndex-startIndex;  var sample=0;  for (var i=startIndex; i<= endIndex; i++) {    weighted=weighted+((dataIn[i]/total)*(sample/nSpan));    sample=sample+1;  }  return weighted;}";
Serial serial;

//variables for detecting mouse move
boolean pauseOnMouseMove=true;
int oldMouseY=0;
int oldMouseX=0;

//fft objects for analysis of EEG data
Minim minim;
FFT  sampleAnalyzer;
FFT bufferAnalyzer;

Robot robot;
MindSet eeg;
boolean foundNeurosky; //used to indicate when Neurosky port autodetection has worked

PrintWriter logger; //for writing logs from scripts
boolean visible=true; //is the overlay currently visisble?
//frequency and amplitude of oscillation
float frequency=15;
float amplitude=0.25;

int lastCycleStart=millis(); //timing for oscillator
int opMode=1;
boolean firstRun=true;

//ui fonts
PFont font;
PFont smallfont;

int mouseCom=millis(); //time mouse has been in the corner (after a certain delay this will bring up the options screen)

String script=""; //contents of user script
String sessionStore=""; //session store for user script

//booleans for settings screen
boolean hasScript=false;
boolean eegFail=false;
boolean eegConnected=false;
boolean mouseState=false;
boolean scriptError=false;
boolean isVis=true;

//script stuff
ScriptEngineManager mgr = new ScriptEngineManager();
ScriptEngine engine = mgr.getEngineByName("javascript");
//timing for script
int scriptStartTime=0;
//buffers for raw data
float[] lastSample;
float[] sampleBuffer;
int sampCounter=0;

//lengths of baseline and individual samples (# data points)
int sampleLength;
int baselineLength;

boolean continuousBaseline; //use a moving average baseline?

int baselineSample=0;

boolean mouseOverride=false; //if true, make window transparent to let mouse activity pass through.


float[] windowSignal(float[] input) { //apply a Hann window to the signal in order to improve the spectrum
  float[] output=new float[input.length];
  for (int i=0; i< input.length; i++) {
    output[i]=input[i]*(float)Math.pow(Math.sin((Math.PI*(i+1))/input.length),2);
  }
  return output;
}

int nextPow2(int number) { //ghetto way of finding powers of 2 for FFT
  int exp=1;
  boolean keepRunning=true;
  while (true) {
    int test=(int)Math.pow(2,exp);
    if (test >= number) {
      return test;
    }
    exp++;
  }
}

public void rawEvent(int[] sig) { //for OpenBCI our signal is floats, for neurosky it's ints. This lets us handle both without losing precision in the openBCI data

  foundNeurosky=true; //if we are searching for the correct port, let the search loop know we found it

  float[] sig2=new float[sig.length];
  for (int i=0; i<sig.length;i++) {
    sig2[i]=(float)sig[i];
  }
  try {
  rawEvent(windowSignal(sig2));
  }
  catch (Exception e) {
    print("Couldn't process sample (this is OK unless it happens a lot)");
  }
  
  
}


public void rawEvent(float[] sig) {  //called by the mindset library when a new packet of 512 raw values (1 second) of data is avilable from the Neurosky device.
  eegConnected=true;
  
  for (int i=0; i< sig.length; i++) {
    lastSample[sampCounter]=sig[i]*((float)baselineLength/(float)sampleLength); //
    sampCounter++;
    if (!continuousBaseline) { //if not a continuous baseline, keep adding to the baseline buffer until it is full
      if (baselineSample < sig.length*baselineLength) {
        sampleBuffer[baselineSample]=sig[i];
        baselineSample++;
      }
    }
      else { //for a continuous baseline, shift the samples by 1 in the array and add the latest at the end of the buffer.
    for (int samp=0; samp< (baselineLength*sig.length)-1; samp++) {
      sampleBuffer[samp]=sampleBuffer[samp+1]; //ineffcient? yes. But it's harder to mess up this way. Not that I didn't manage it at some point.
  }
  sampleBuffer[(baselineLength*sig.length)-1]=sig[i]; 
      }
  }
  if (sampCounter >= (sig.length*sampleLength)) { //we've acquired enough samples, time to process them.
    sampCounter=0;
    //println(lastSample);
    processData(lastSample, sampleBuffer);
  }
  
}


void processData(float[] sample, float[] history) {
  print(sample.length+",");
  println();
  for (int i=0; i < 10; i++) {
    print(sample[i]+",");
  }
  sampleAnalyzer.forward(sample);
  bufferAnalyzer.forward(history);
  float[] baselineSpectrum=new float[1000];
  float[] sampleSpectrum=new float[1000];
  int si=0;
  for (float freq=0.1; freq <=100; freq=freq+0.1) { //each bin in spectrum increase by 0.1 Hz.
    baselineSpectrum[si]=bufferAnalyzer.getFreq(freq);
    sampleSpectrum[si]=sampleAnalyzer.getFreq(freq);
    si++;
  
   
  }
   println("");
   if (hasOpenBCI) {
  lastSample=new float[nextPow2(200*baselineLength)]; //reset the sample buffer.
   }
   else {
     lastSample=new float[nextPow2(512*baselineLength)]; //reset the sample buffer.
   }

    runScript(baselineSpectrum, sampleSpectrum); //pass the spectra to the script
}


void runScript(float[] baseline, float[] sample) { //run a user neuroffedback script, called each time we get a new batch of data (frequency depends on the sample length set in the scrpt)
  //if we should be excuting a scright, update the script values
      if (hasScript) {
        try {
        engine.put("lastSample",sample);
        engine.put("baseline",baseline);
        engine.put("sessionStore",sessionStore);
        engine.put("runTime",millis()-scriptStartTime);
        engine.eval(jsfunctions+script);
        Double amp=(Double)engine.get("amplitude");
        amplitude=(amp.floatValue()*(scriptAmplitude*2));
        Double freq=(Double)engine.get("frequency");
        frequency=freq.floatValue();
        sessionStore=(String)engine.get("sessionStore");
        try {
         String logData=(String)engine.get("logData");
        logger.println(logData);
        }
        catch (Exception e) { //non logging script
          println("No data to log");
        }
        }
        catch (javax.script.ScriptException e) {
         
          println("Error parsing script");
          println(e.getMessage());
          hasScript=false;
          scriptError=true;
          eeg.quit();
        }

        
      }
  
  
}

void oscEvent(OscMessage message) { //called when we get an OSC message from OpenBCI
  hasOpenBCI=true;
  eegConnected=true;
  if (hasScript) { //script is running
    if (openBCIPointer < 200) {
      openBCIBuffer[openBCIPointer]=message.get(0).floatValue();
      openBCIPointer++;
    }
    else {
      rawEvent(windowSignal(openBCIBuffer));
      openBCIPointer=0;
      openBCIBuffer=new float[200];
    }
  }
}


void setup() { 
  size(displayWidth,displayHeight);
  background(200);
  receiver=new OscP5(this,12345);

//do some black magick to get the flashy thing to work
  frame.removeNotify();
  frame.setUndecorated(true);
  frame.setFocusableWindowState(false);
  frame.setAlwaysOnTop(true);
  AWTUtilities.setWindowOpacity(frame, 0.5f);
  //AWTUtilities.setWindowOpaque(frame,false);
  frame.addNotify();
 //createGUI();
  frameRate(200);
  
   try { 
    robot = new Robot();
    robot.setAutoDelay(0);
  } 
  catch (Exception e) {
    e.printStackTrace();
}
background(255,255,255);
font = createFont("font.vlw", 48);
smallfont = createFont("font.vlw", 32);
textFont(font);
minim = new Minim(this); //setup minim for ffts later;


//To make our window "transparent" to click events we need to intercept them, hide the window (make it 100% tranparent) and then rebroadcast them so they reach the underlying application.
//Also, we need to KEEP the window transparent while the mouse is held so that if the user is doing something like a drag the events keep reaching the correct application
//There are a lot of ways to do this that SEEM like they should work but don't. Beware of messing with this part!


//the global mouse listener will let us pick up mouse events even when the window is invisible
  mouseHook = new GlobalMouseHook();
  mouseHook.addMouseListener(new GlobalMouseAdapter() {
      @Override public void mousePressed(GlobalMouseEvent event)  {
        
        if (opMode == 2 || opMode == 5) {
        if (event.getButton()==GlobalMouseEvent.BUTTON_LEFT) {
         
         if (frame.isVisible() && !leftDown && !overTaskbar) { //only do this if the window is actually visible. Also the window interacts weirdly with the task bar, so we make it totally transparent when the mouse is over the taskbar. We have to disable sending clicks in the taskbar case because if we didn't a single click would become a double click.
            mouseOverride=true; //mouse has been pressed, tell the draw() thread to make the window invisible



            frame.setVisible(false);
           
           
            
              fakeRelease=fakeRelease+1;
              
              //why do we need to do this set of three things? Who the fuck knows.
              robot.mousePress(InputEvent.BUTTON1_DOWN_MASK);
              robot.mouseRelease(InputEvent.BUTTON1_DOWN_MASK);
              robot.mousePress(InputEvent.BUTTON1_DOWN_MASK);

             
            
            
            mouseOverride=false;
            isVis=false;

            thread("resetFrame"); //monitor the mouse state and reinstate flashing when it is no longer pressed
           // opMode=2;
          }
          leftDown=true; //don't do this again until button has been released
          
        }
        //the other two mouse buttons are the same
        if (event.getButton()==GlobalMouseEvent.BUTTON_MIDDLE) {
            
         if (frame.isVisible() && !middleDown && !overTaskbar) {
            mouseOverride=true;

            frame.setVisible(false);
            fakeRelease=fakeRelease+1;
            robot.mousePress(InputEvent.BUTTON2_DOWN_MASK);
            robot.mouseRelease(InputEvent.BUTTON2_DOWN_MASK);
            robot.mousePress(InputEvent.BUTTON2_DOWN_MASK);
            isVis=false;
            resetFrame();
          }
          middleDown=true;
        }
        if (event.getButton()==GlobalMouseEvent.BUTTON_RIGHT) {
           
         if (frame.isVisible() && !rightDown && !overTaskbar) {
            mouseOverride=true;

            println("Right Click event");
            frame.setVisible(false);
            fakeRelease=fakeRelease+1;
            robot.mousePress(InputEvent.BUTTON3_DOWN_MASK);
            robot.mouseRelease(InputEvent.BUTTON3_DOWN_MASK);
            robot.mousePress(InputEvent.BUTTON3_DOWN_MASK);
            isVis=false;
            resetFrame();
          }
          rightDown=true;
        }
        }
      }
      @Override public void mouseReleased(GlobalMouseEvent event)  {
        if (fakeRelease <= 0) {
          //if the mouse got released by the user and it's not a fake event generated by Robot, update these variables to tell resetFrame() that we are done and re-prime the system for another press.
        if (event.getButton()==GlobalMouseEvent.BUTTON_LEFT) {
          leftDown=false;
          
          }
          
        
        if (event.getButton()==GlobalMouseEvent.BUTTON_MIDDLE) {
          middleDown=false;
        }
        if (event.getButton()==GlobalMouseEvent.BUTTON_RIGHT) {
          rightDown=false;
        }
        

      }
      fakeRelease = fakeRelease - 1;
      if (fakeRelease < 0) {
        fakeRelease=0;
      }
      }
     
    
});

leftDown=rightDown=middleDown=false; //reinitialize this in case mouse clicks during intialize got detected
openBCIBuffer=new float[200];
}

void draw() {


  if (opMode == 1) { //settings screen, takes over the display with full opacity.
      frameRate(200);
      AWTUtilities.setWindowOpacity(frame, 1.0f);
      frame.setFocusableWindowState(true);
      frame.setAlwaysOnTop(false);
      background(0);
      
      //draw scaffolding for UI
      if (hasScript) {
        stroke(100);
      }else {
      stroke(255);
      }
      strokeWeight(3);
      noFill();
      
      rect(100,200,200,50); //Frequency bar
      
      rect(100,350,200,50); //Amplitude bar
      stroke(255);
      rect(100,470,200,100); //Back button
      stroke(230,0,0);
      rect(350,470,200,100); //Exit button
      stroke(255);
      rect(480,200,300,100); //Load button
      //mouse pause control
      rect(100,670,50,50);
      textFont(font);
      if (pauseOnMouseMove) {
      text("X",110,710); //mark as checked
      }
      
      if (hasScript) {
        fill(100);
      }
      else {
      fill(255);
      }
      textFont(font);
      text("Frequency",100,180);
      text("Amplitude",100,330);
      fill(255);
      text("Start",110,480+50);
      
      text("Exit",360,480+50);
      text("Pause flicker when mouse is moved", 165,710);
      textFont(smallfont);
      text("This improves compatibility with some applications",165,740);
      textFont(font);
      if (hasScript) {
        stroke(255);
        strokeWeight(3);
        noFill();
        rect(850,200,200,50); //Script amplitude control
        fill(255);
        rect(850+(scriptAmplitude*200),190,10,70);
        textFont(smallfont);
        fill(255);
        text("Script amplitude",850,285);
        text(scriptAmplitude * 200 +"%",1070,215);
        textFont(font);
        fill(240,240,0);
        text("Stop script",490,260);
        fill(100);
        stroke(100);
        
        
      }
      else {
      fill(255);
      text("Load script",490,260);
      }
      rect(100+(frequency*6.66666666667),190,10,70);
      rect(100+(amplitude*200),340,10,70);
      textFont(smallfont);
      text(frequency+" Hz",320,250);
      text((amplitude*100)+" %",320,400);
      
      if (eegFail) {
        textFont(font);
        fill(230,0,0);
        text("Could not connect to EEG",490,360);
      }
      
        if (eegConnected) {
        textFont(font);
        fill(0,230,0);
        text("EEG system connected",490,360);
      }
              if (hasOpenBCI) {
        textFont(font);
        fill(255);
        text("OpenBCI connected\nReading channel 1",490,460);
      }
      
      if (scriptError) {
        textFont(font);
        fill(230,0,0);
        text("The script encountered\nan error and was stopped",780,200);
      }
 
      
      if (mouseX < 450 && mouseY < 450 && mouseY >= 100 && hasScript) {
        fill(100);
        textFont(smallfont);
        text("Settings controlled by script",mouseX+15,mouseY);
      }
      
     //draw the active zones
     fill(200,200,0,100);
     stroke(230,230,0,100);
     rect(width-100,height-100,100,100); //bottom right
     rect(0,0,20,20); 
     textFont(smallfont);
     fill(255);
     stroke(255);
     text("You can pull up this screen\nby holding the mouse \nin the right bottom\nor top left corner.",width-500,height-200);
     

  }
  if (opMode == 2) {
   // frame.setAlwaysOnTop(true);
//get mouse pointer loctation
PointerInfo info = MouseInfo.getPointerInfo();
Point loc = info.getLocation();
if (pauseOnMouseMove) { //reset the flickerstart time one second in the future if we are pausing on mouse move and a move occurred
if (abs((int)loc.getY()- oldMouseY) > 3 || abs((int)loc.getX()- oldMouseX) > 3) {
  startFlickerTime=millis()+1000;
}
oldMouseX=(int)loc.getX();
oldMouseY=(int)loc.getY();
}

     
      frame.setAlwaysOnTop(true); //overlay is always on top
      frame.setFocusableWindowState(false);  //prevent the flashing overlay from ever gaining keyboard focus 
      
      
      if (millis() - mouseCom >= 2000) { //if mouse has been in the corner for more than 2 seconds pull up settings
        opMode=1;
      }
      else {
      frameRate(200);
      background(255);
  float halfWave=((float)1000/frequency)/(float)2;
  if (millis() - lastCycleStart >= halfWave) {
    visible=!visible;
    if ((int)loc.getY()  < displayHeight-40 && millis() > startFlickerTime ) { //make the window go away if mouse is over the taskbar or we just moved it and the "pause if mouse moved" option is on
      overTaskbar=false;
      
      
    if (!mouseOverride ) {  //also hide the window if we got a mouse override or just picked up a mouse click
      
      frame.setAlwaysOnTop(true);
    if (visible) { //on phase of the cycle
      if (amplitude > 1) {
        amplitude=1;
      }
      if (amplitude < 0) {
        amplitude=0;
      }

  AWTUtilities.setWindowOpacity(frame, amplitude);
  }
  else{ //off phase of the cycle

      AWTUtilities.setWindowOpacity(frame, 0.01f); //going totally transparent on each cycle causes problems so do this instead (if window is transparent all clicks pass through automatically, and the OS transparency handling is slow and can't be synced with our mouse click handling routines)
      
  }
    }
    else {
      AWTUtilities.setWindowOpacity(frame, 0.00f); //override, go transparent
    }
    }
    else { //over taskbar or mouse moved recently, go transparent
      overTaskbar=true;
            AWTUtilities.setWindowOpacity(frame, 0.00f);
    }
  
  
 
lastCycleStart=millis();


  }
      }
  
      if (mouseX > width-100 && mouseY > height-100 || (mouseX <= 20 && mouseY <=20) ) { //keep track of how long mouse has been in one of the active zones to pull up settings

    }
      else {
        mouseCom = millis();
      }
 
  }




}


void handleSettings() { //handles mouse interactions with GUI elements on settings screen.
  if (mouseX>=100 && mouseX <=300) { //x ccordinates for sliders
      if (mouseY >=190 && mouseY <= 190+70) { //frequency
        frequency=round((mouseX-100)/6.66666666667);
      }
      if (mouseY >=340 && mouseY <= 340+70) { //amplitude
        amplitude=(float)(mouseX-100)/(float)200;
      } 
    
  }
    
if (hasScript) {
    if (mouseX >= 850 && mouseX <= 1050 && mouseY >= 190 && mouseY <= 260) {
      scriptAmplitude=(float)(mouseX-850)/(float)200;
    }
    } 
 if (mouseY >= 470 && mouseY <= 570) { //this is a button click
 if (mouseX>=100 && mouseX <= 300) { //back button click
 leftDown=rightDown=middleDown=false; //reinitialize this in case mouse clicks during intialize got detected

   opMode=2;
 }
  if (mouseX>=350 && mouseX <= 550) { //exit button click
   exit();
 }
   
 } 
 

 if (mouseX >= 480 && mouseX <=480+300 && mouseY >=200 && mouseY <=300) { //load/stop was clicked
     if (hasScript) {
       hasScript=false;
       if (!hasOpenBCI) {
       eeg.quit();
       }
     }
     else {
     selectInput("Select the script file", "fileSelected");
     }
 }
  }
  
  void fileSelected(File selection) { //called when user selects a scriipt file from file chooser
  if (selection == null) {
    println("Window was closed or the user hit cancel.");
  } else {
    
    //set default script values
    sampleLength=1;
    baselineLength=16;
    continuousBaseline=true;
    baselineSample=0;
    String[] result=loadStrings(selection.getAbsolutePath());
    script="";
    for (int i=0; i<result.length; i++) {
      if (result[i].indexOf("//") == -1) {
      script=script+result[i];
      }
  }
  hasScript=true;
  scriptError=false;
  for (int line=0; line < result.length; line++) {
  
    if (result[line].indexOf("sampleLength=") > -1) {
      println("Sample length:"+result[line].substring(result[line].indexOf("sampleLength=")+13));
      sampleLength=int(result[line].substring(result[line].indexOf("sampleLength=")+13));
    }
      if (result[line].indexOf("baselineLength=") > -1) {
      println("Baseline length:"+result[line].substring(result[line].indexOf("baselineLength=")+15));
      baselineLength=int(result[line].substring(result[line].indexOf("baselineLength=")+15));
    }
    
     if (result[line].indexOf("baselineMode=startup") > -1) { //tell the system not to do continuous baselining
      continuousBaseline=false;
    }
    if (result[line].indexOf("//sessionStore=") > -1) { //initialize the persistent store
      sessionStore=result[line].substring(result[line].indexOf("//sessionStore=")+15).replace("\n","").replace("\r","");
    }
  }
  
  if (baselineLength < sampleLength) {
    baselineLength=sampleLength;
  }
  boolean worked=false;
  String[] ports=serial.list();
  foundNeurosky=false; //reset before searching
  if (!hasOpenBCI) {
  for (int port=ports.length-1; port >= 0; port--) {
      println(ports[port]);
      eeg = new MindSet(this, ports[port]);
      long startMillis=millis();
      while (millis() < startMillis + 3000) { //stall while waiting for a connection
      }
      if (foundNeurosky) {
        worked=true;
        break;
      }
      
  }
  }
  else {
    worked=true;
  }
  scriptStartTime=millis();
  logger = createWriter("log-"+year()+"-"+month()+"-"+day()+"-"+hour()+"-"+minute()+".txt"); 
  if (!worked) {
    print("Unable to connect to EEG headset");
    eegFail=true;
  }
  
  if (hasOpenBCI) { //openBCI has a 200 Hz sampling rate, Neurosky has 512
  lastSample=new float[nextPow2(200*baselineLength)];
  sampleBuffer=new float[nextPow2(200*baselineLength)];
    sampleAnalyzer=new FFT(sampleBuffer.length,200);
  bufferAnalyzer=new FFT(sampleBuffer.length,200);
  }
  else {
  lastSample=new float[nextPow2(512*baselineLength)];
  sampleBuffer=new float[nextPow2(512*baselineLength)];
  sampleAnalyzer=new FFT(sampleBuffer.length,512);
  bufferAnalyzer=new FFT(sampleBuffer.length,512);
  }
  //sampleAnalyzer.window(FFT.HAMMING);
  //bufferAnalyzer.window(FFT.HAMMING);
  }
}
  


//these functions catch mouse events on the settings screen
void mouseDragged() {
    if (opMode ==1) {
      handleSettings();
    }
    

    
}                          

void mousePressed() {
if (opMode == 1) {
  handleSettings();
}
}

void mouseClicked() {
  if (opMode == 1) { //toggling the mouse movement option needs to be done on mouse click, not mouse press, so that each click gives you only one toggle.
  if (mouseX > 100 && mouseX < 150 && mouseY > 670 && mouseY < 720) {
    pauseOnMouseMove=!pauseOnMouseMove;
    
  }
  handleSettings();
}


 
}

void mouseWheel() {
  if (opMode == 2) {
    startFlickerTime=millis()+1000;
  }
}
  
  
  


  



void exit() { //clean shutdown
  println("Exiting");
  if (eegConnected) {
    if (!hasOpenBCI) { //todo:make sure this doesn't break if neorusky gets connected later
  eeg.quit();
    }
    if (logger != null) {
   logger.flush();
  logger.close();
    }
  
  }
  super.exit();
}

 
void resetFrame() { //resttore flahsing when the mouse is no longer being held. Started after mouse handler detects a button down and pauses flashing

    while (leftDown || middleDown || rightDown) {

    }

  mouseCom=millis();
  isVis=true;
  frame.setVisible(true);
  frame.setAlwaysOnTop(true);
  
 

  
  
}
  



