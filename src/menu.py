#!/usr/bin/python3
from enum import Enum
from . import config_base

def radiolist(title:str,question:str,choices):
    invalid_input=True
    while(invalid_input):
        print(f"#### {title} ####\n")
        print(question)
        index = {}
        counter = 1
        if isinstance(choices,dict):
            for choice in choices.keys():
                if len(choice) <= 12:
                    sep="\t\t"
                else:
                    sep="\t"
                print(f"{counter})  {choice}{sep}{choices[choice]}")
                index[str(counter)] = choice
                counter = counter + 1
        elif isinstance(choices,list):
            for choice in choices:
                print(f"{counter})  {choice}")
                index[str(counter)] = choice
                counter = counter + 1
        else:
            print (f"object 'choices': {type(choices)} objects are unsupported.")
        selected = input("Type in number:  ")
        if selected in index.keys():
            print("\n")
            return index[selected]
    
def question(title:str,q:str,returntype, default, validation=None):
    print(f"#### {title} ####\n")
    if str(returntype.name) == "Boolean":
        if default == True:
            suggest = "Y/n"
        else:
            suggest = "y/N"
        a = input(f"{q} [{suggest}]\n")
        if "y" in str(a).lower():
            return True
        elif "n" in str(a).lower():
            return False
        else:
            return default
    elif str(returntype.name) == "Integer":
        invalid_input = True
        while(invalid_input):
            a = input(f"{q} [{default}]\n")
            if str(a) == "" or f"{str(default)}" == str(a):
                return default
            else:
                try:
                    valid = validation(int(a))
                    if valid:
                        return int(a)
                except:
                    pass
    else:
        a = input(f"{q} [{default}]\n")
        if a == '':
            return default
        else:
            return a


class qType(Enum):
    Boolean = 0
    Integer = 1
    String = 2
    IPAdress = 3
    CIDR = 4