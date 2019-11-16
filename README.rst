########################################
Capture The Flag With Stuff Glyph Module
########################################

This is a hardware device designed to assist the `CMU KGB
<http://www.cmukgb.org/>`_ game of `Capture The Flag With Stuff
<http://www.cmukgb.org/activities/ctfws.php>`_.

The device functions more or less as a glorified stopwatch under centralized
control; see
https://github.com/cmukgb/ctfws-timer-host/blob/master/protocol/protocol.rst
for the gory details.  Almost surely, though, you'll be interacting with these
via http://timer.cmukgb.org/judge (a deployment of
https://github.com/cmukgb/ctfws-timer-web).

Character Display Examples
##########################

* Setup time display::

    0         1         
    01234567890123456789
    SETUP 2   :  MM:SS.s
       NN⚑: R=0 y=0
    messagemessagemessag
    START IN     MM:SS.s

* Steady state display::

    0         1         
    01234567890123456789
    GAME 2    :  MM:SS.s
       NN⚑: R=NN y=NN
    messagemessagemessag
    JB n/N IN    MM:SS.s

* Last round display::

    0         1         
    01234567890123456789
    GAME 2    :  MM:SS.s
       NN⚑: R=NN y=NN
    messagemessagemessag
    GAME END IN  MM:SS.s

* Game over::

    0         1         
    01234567890123456789
     CMUKGB CTFWS TIMER
       NN⚑: R=NN y=NN
    messagemessagemessag
     GAME OVER @ MM:SS

* Game not configured::

    0         1         
    01234567890123456789
     CMUKGB CTFWS TIMER
       
    messagemessagemessag
     GAME NOT CONFIGURED


